#!/usr/bin/env bash
# adapter-validation.sh -- semantic adapter.json validation for multi-cli.
#
# Bash mirror of lib/MultiCli.AdapterValidation.psm1. Beyond the JSON schema,
# these checks enforce the contracts the launchers rely on: declared paths are
# relative and traversal-free, credential/shared/session/unsafe lists never
# overlap, placeholders come from the known set, and every unsupported support
# row carries the reason why.
#
# Entry point: validate_adapter_manifest <manifest> <expected-id>. Errors
# accumulate in ADAPTER_VALIDATION_ERRORS (reset per call); returns 0 when the
# list is empty, 1 otherwise.

ADAPTER_VALIDATION_ERRORS=()

adapter_validation_error() {
  ADAPTER_VALIDATION_ERRORS+=("$1")
}

# True when $1 is a non-empty relative path with no drive letter, colon, or
# '..' component -- safe to join under a state root.
is_safe_adapter_path() {
  local path="${1//\\//}"
  [ -n "${path//[[:space:]]/}" ] || return 1
  [ "$path" != null ] || return 1
  case "$path" in
    /*|\\*|[a-zA-Z]:*|*:*|.|..|../*|*/../*|*/..) return 1 ;;
  esac
  return 0
}

# True when two declared paths are equal or one contains the other. Compared
# case-insensitively: declared paths land on case-insensitive filesystems
# (Windows, default macOS), where 'Auth.json' and 'auth.json' are one file.
adapter_paths_overlap() {
  local left="${1//\\//}" right="${2//\\//}"
  left="$(printf '%s' "${left%/}" | tr '[:upper:]' '[:lower:]')"
  right="$(printf '%s' "${right%/}" | tr '[:upper:]' '[:lower:]')"
  [ "$left" = "$right" ] || [[ "$left" == "$right"/* ]] || [[ "$right" == "$left"/* ]]
}

# Record an error for every entry of the jq array at $2 that is not a safe
# relative path; $3 labels the list in messages.
validate_adapter_path_list() {
  local manifest="$1" jq_path="$2" label="$3" value
  while IFS= read -r value; do
    [ -z "$value" ] && continue
    is_safe_adapter_path "$value" || adapter_validation_error "$label '$value' must be a safe relative path"
  done < <(jq -r "$jq_path // [] | .[]?" "$manifest" 2>/dev/null | tr -d '\r')
}

# Record an error for any pair of entries across two jq array paths that
# overlap (a credential path nested under a shared path would leak).
validate_adapter_path_separation() {
  local manifest="$1" left_path="$2" left_label="$3" right_path="$4" right_label="$5"
  local left right
  while IFS= read -r left; do
    [ -z "$left" ] && continue
    while IFS= read -r right; do
      [ -z "$right" ] && continue
      if adapter_paths_overlap "$left" "$right"; then
        adapter_validation_error "$left_label '$left' overlaps $right_label '$right'"
      fi
    done < <(jq -r "$right_path // [] | .[]?" "$manifest" 2>/dev/null | tr -d '\r')
  done < <(jq -r "$left_path // [] | .[]?" "$manifest" 2>/dev/null | tr -d '\r')
}

# Reject any {placeholder} outside the known set; an unknown one would expand
# to a literal brace directory at launch time.
validate_adapter_placeholders() {
  local manifest="$1" placeholder
  while IFS= read -r placeholder; do
    case "$placeholder" in
      '{profileDir}'|'{profileId}'|'{authDir}'|'{runtimeRoot}'|'{sharedStateRoot}'|'{realHome}') ;;
      *) adapter_validation_error "unknown placeholder '$placeholder'" ;;
    esac
  done < <(jq -r '.. | strings | scan("\\{[A-Za-z][A-Za-z0-9_]*\\}")' "$manifest" 2>/dev/null | tr -d '\r' | sort -u)
}

validate_adapter_object_fields() {
  local manifest="$1" path="$2" allowed="$3" label="$4" key
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    if ! printf '%s\n' "$allowed" | grep -qxF "$key"; then
      if [ -n "$label" ]; then
        adapter_validation_error "unsupported field '$label.$key'"
      else
        adapter_validation_error "unsupported top-level field '$key'"
      fi
    fi
  done < <(jq -r "$path // {} | keys[]?" "$manifest" 2>/dev/null | tr -d '\r')
}

validate_adapter_fields() {
  local manifest="$1" schema_version="$2" top_level
  top_level=$'schemaVersion\nid\ndisplayName\nkind\nbinary\nisolation\ninstall\nversionCommand'
  if [ "$schema_version" -eq 1 ]; then
    top_level+=$'\nshare\nsession\nstatus'
  else
    top_level+=$'\naccount\nnormalState\nconcurrency\nsupport\nappx'
  fi
  validate_adapter_object_fields "$manifest" '.' "$top_level" ''
  validate_adapter_object_fields "$manifest" '.isolation' $'strategy\nmode\nenv\nclearEnv\nargs\nshareFromRealHome' 'isolation'
  if [ "$schema_version" -eq 1 ]; then
    validate_adapter_object_fields "$manifest" '.share' $'systemHome\nlinkable\nneverLink' 'share'
    validate_adapter_object_fields "$manifest" '.session' $'portable\npaths\ncredentials\nreason\nresumeHint' 'session'
    return
  fi
  validate_adapter_object_fields "$manifest" '.account' $'mechanism\ncredentialFiles\ncredentialPrecedence\nlogoutScope\nreason\nsecret' 'account'
  validate_adapter_object_fields "$manifest" '.account.secret' 'environmentVariable' 'account.secret'
  validate_adapter_object_fields "$manifest" '.normalState' $'root\nruntimeSubdir\nsharedPaths\nsessionPaths\nfilePaths\nunsafePaths' 'normalState'
  validate_adapter_object_fields "$manifest" '.normalState.root' $'windows\nmacos\nlinux' 'normalState.root'
  validate_adapter_object_fields "$manifest" '.concurrency' $'level\nsingletonScope' 'concurrency'
  validate_adapter_object_fields "$manifest" '.appx' $'packageName\napplicationId\nstoreProductId' 'appx'
  validate_adapter_object_fields "$manifest" '.support' $'windows\nmacos\nlinux' 'support'
  local platform
  for platform in windows macos linux; do
    validate_adapter_object_fields "$manifest" ".support.$platform" $'level\nreason' "support.$platform"
  done
}

# Platform keys must be exactly windows/macos/linux; schema-v2 additionally
# requires at least one binary candidate per platform.
validate_adapter_binary() {
  local manifest="$1" schema_version="$2" key platform_count
  while IFS= read -r key; do
    case "$key" in
      windows|macos|linux) ;;
      darwin) adapter_validation_error "binary uses unsupported platform key 'darwin'; use 'macos'" ;;
      *) adapter_validation_error "binary uses unsupported platform key '$key'" ;;
    esac
  done < <(jq -r '.binary // {} | keys[]?' "$manifest" 2>/dev/null | tr -d '\r')

  if [ "$schema_version" -eq 2 ]; then
    for key in windows macos linux; do
      platform_count="$(jq -r ".binary.$key | if type == \"array\" then length else 0 end" "$manifest" 2>/dev/null)"
      [ "$platform_count" -gt 0 ] || adapter_validation_error "binary.$key must contain at least one candidate"
    done
  fi
}

# Schema-v1 (legacy whole-root isolation): a known strategy plus safe,
# non-overlapping share/session path lists.
validate_adapter_v1() {
  local manifest="$1" strategy
  strategy="$(jq -r '.isolation.strategy // empty' "$manifest")"
  case "$strategy" in
    env|userDataDir|redirectHome|appdata|sandboxUser) ;;
    *) adapter_validation_error "isolation.strategy '$strategy' is not supported for schema-v1" ;;
  esac

  validate_adapter_path_list "$manifest" '.share.linkable' 'share.linkable path'
  validate_adapter_path_list "$manifest" '.share.neverLink' 'share.neverLink path'
  validate_adapter_path_list "$manifest" '.session.paths' 'session path'
  validate_adapter_path_list "$manifest" '.session.credentials' 'credential path'
  validate_adapter_path_separation "$manifest" '.share.linkable' 'share.linkable path' '.share.neverLink' 'share.neverLink path'
  validate_adapter_path_separation "$manifest" '.session.paths' 'session path' '.session.credentials' 'credential path'
}

# Every platform row needs a level. Experimental and unsupported rows require
# a reason; supported rows may include one for mode requirements.
validate_adapter_support() {
  local manifest="$1" platform level reason
  for platform in windows macos linux; do
    level="$(jq -r ".support.$platform.level // empty" "$manifest")"
    case "$level" in
      supported) ;;
      experimental)
        reason="$(jq -r ".support.$platform.reason // empty" "$manifest")"
        [ -n "$reason" ] || adapter_validation_error "support.$platform.reason is required for level 'experimental'"
        ;;
      unsupported)
        reason="$(jq -r ".support.$platform.reason // empty" "$manifest")"
        [ -n "$reason" ] || adapter_validation_error "support.$platform.reason is required for level 'unsupported'"
        ;;
      verified)
        adapter_validation_error "support.$platform.level 'verified' was retired; use 'supported', 'experimental', or 'unsupported'"
        ;;
      *) adapter_validation_error "support.$platform.level must be supported, experimental, or unsupported" ;;
    esac
  done
}

# Schema-v2 (accountOverlay): account mechanism with its required fields,
# concurrency declaration, per-platform state roots, and full separation
# between credential, shared, session, and unsafe path lists.
validate_adapter_v2() {
  local manifest="$1" strategy mode mechanism concurrency reason
  strategy="$(jq -r '.isolation.strategy // empty' "$manifest")"
  [ "$strategy" = accountOverlay ] || adapter_validation_error "isolation.strategy must be 'accountOverlay' for schema-v2"

  mode="$(jq -r '.isolation.mode // empty' "$manifest")"
  case "$mode" in foreground|detached) ;; *) adapter_validation_error "isolation.mode must be 'foreground' or 'detached'" ;; esac

  mechanism="$(jq -r '.account.mechanism // empty' "$manifest")"
  case "$mechanism" in
    fileOverlay)
      [ "$(jq -r '.account.credentialFiles | if type == "array" then length else 0 end' "$manifest")" -gt 0 ] || \
        adapter_validation_error "account.credentialFiles must not be empty for fileOverlay"
      ;;
    processSecret)
      [ -n "$(jq -r '.account.secret.environmentVariable // empty' "$manifest")" ] || \
        adapter_validation_error "account.secret.environmentVariable is required for processSecret"
      ;;
    osUserCredentialStore) ;;
    inseparable)
      reason="$(jq -r '.account.reason // empty' "$manifest")"
      [ -n "$reason" ] || adapter_validation_error "account.reason is required for inseparable state"
      ;;
    *) adapter_validation_error "account.mechanism '$mechanism' is not supported" ;;
  esac

  if jq -e '.appx != null' "$manifest" >/dev/null 2>&1; then
    local package_name
    package_name="$(jq -r '.appx.packageName // empty' "$manifest")"
    [ -n "$package_name" ] || \
      adapter_validation_error "appx.packageName is required when appx is declared"
    [ -n "$(jq -r '.appx.applicationId // empty' "$manifest")" ] || \
      adapter_validation_error "appx.applicationId is required when appx is declared"
    [ "$mechanism" = osUserCredentialStore ] || \
      adapter_validation_error "appx requires account.mechanism osUserCredentialStore"
    [ "$(jq -r '.isolation.mode // empty' "$manifest")" = detached ] || \
      adapter_validation_error "appx requires isolation.mode detached"
    if [ -n "$package_name" ] && ! jq -e --arg target "appx:$package_name" '.binary.windows | index($target) != null' "$manifest" >/dev/null 2>&1; then
      adapter_validation_error "binary.windows must contain 'appx:$package_name' when appx is declared"
    fi
  fi

  concurrency="$(jq -r '.concurrency.level // empty' "$manifest")"
  case "$concurrency" in multiWriter|singleWriter|unsupported) ;; *) adapter_validation_error "concurrency.level is invalid" ;; esac
  [ -n "$(jq -r '.concurrency.singletonScope // empty' "$manifest")" ] || adapter_validation_error "concurrency.singletonScope is required"

  local platform
  for platform in windows macos linux; do
    [ -n "$(jq -r ".normalState.root.$platform // empty" "$manifest")" ] || \
      adapter_validation_error "normalState.root.$platform is required"
  done
  local state_subdir
  state_subdir="$(jq -r '.normalState.runtimeSubdir // empty' "$manifest")"
  if [ -n "$state_subdir" ]; then
    is_safe_adapter_path "$state_subdir" || adapter_validation_error "normalState.runtimeSubdir '$state_subdir' must be a safe relative path"
  fi

  validate_adapter_path_list "$manifest" '.account.credentialFiles' 'credential path'
  validate_adapter_path_list "$manifest" '.normalState.sharedPaths' 'shared path'
  validate_adapter_path_list "$manifest" '.normalState.sessionPaths' 'session path'
  validate_adapter_path_list "$manifest" '.normalState.filePaths' 'file path'
  validate_adapter_path_list "$manifest" '.normalState.unsafePaths' 'unsafe path'
  validate_adapter_path_separation "$manifest" '.account.credentialFiles' 'credential path' '.normalState.sharedPaths' 'shared path'
  validate_adapter_path_separation "$manifest" '.account.credentialFiles' 'credential path' '.normalState.sessionPaths' 'session path'
  validate_adapter_path_separation "$manifest" '.account.credentialFiles' 'credential path' '.normalState.unsafePaths' 'unsafe path'
  validate_adapter_path_separation "$manifest" '.normalState.sharedPaths' 'shared path' '.normalState.unsafePaths' 'unsafe path'
  validate_adapter_path_separation "$manifest" '.normalState.sessionPaths' 'session path' '.normalState.unsafePaths' 'unsafe path'
  validate_adapter_support "$manifest"
}

# Validate one manifest against the directory it lives in. Collects every
# problem in ADAPTER_VALIDATION_ERRORS (reset at entry) and returns 0 only
# when the manifest is fully compliant.
validate_adapter_manifest() {
  local manifest="$1" expected_id="$2" id schema_version required
  ADAPTER_VALIDATION_ERRORS=()

  if ! jq empty "$manifest" >/dev/null 2>&1; then
    adapter_validation_error "invalid JSON"
    return 1
  fi

  id="$(jq -r '.id // empty' "$manifest")"
  [[ "$id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || adapter_validation_error "id must match ^[a-z0-9][a-z0-9-]*$"
  [ "$id" = "$expected_id" ] || adapter_validation_error "directory '$expected_id' does not match id '$id'"

  for required in displayName kind binary isolation; do
    jq -e ".${required} != null" "$manifest" >/dev/null 2>&1 || adapter_validation_error "$required is required"
  done
  kind="$(jq -r '.kind // empty' "$manifest")"
  case "$kind" in
    cli|ide|gui|hybrid) ;;
    '') ;;
    *) adapter_validation_error "kind '$kind' is not one of: cli, ide, gui, hybrid" ;;
  esac

  schema_version="$(jq -r '.schemaVersion // 1' "$manifest" 2>/dev/null)"
  case "$schema_version" in
    1) validate_adapter_v1 "$manifest" ;;
    2) validate_adapter_v2 "$manifest" ;;
    *)
      adapter_validation_error "schemaVersion '$schema_version' is not supported"
      return 1
      ;;
  esac

  validate_adapter_fields "$manifest" "$schema_version"
  validate_adapter_binary "$manifest" "$schema_version"
  validate_adapter_placeholders "$manifest"
  [ "${#ADAPTER_VALIDATION_ERRORS[@]}" -eq 0 ]
}
