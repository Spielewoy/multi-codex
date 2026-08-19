#!/usr/bin/env bats
# Real-execution tests for `multi-cli new <tool>/<name> --isolated`: whole-root
# isolation for schema-v2 adapters. An isolated profile shares NOTHING with the
# native tool home -- the adapter's home env points at the profile dir itself,
# no runtime overlay is built, and nothing is seeded or linked from the shared
# root. Metadata keeps lifecycle operations on schema-v2 safety paths.
#
# No mocks. Each test builds real fixture adapters under a scratch tools dir,
# runs the real launcher, and asserts on exit code, captured child env, and
# the file tree.

load helpers/common

setup() {
  setup_scratch
  TOOLS_ROOT="$MULTICLI_SCRATCH/tools"
  mkdir -p "$TOOLS_ROOT/fixture" "$TOOLS_ROOT/secretcli" "$TOOLS_ROOT/lockedcli"
  export USERPROFILE="$HOME"
  export APPDATA="$HOME/AppData/Roaming"
  export LOCALAPPDATA="$HOME/AppData/Local"
  export MULTICLI_TOOLS_DIR="$TOOLS_ROOT"
  export MULTICLI_OVERRIDE_BINARY="$MULTICLI_SCRATCH/capture-child"
  export CAPTURE_OUTPUT="$MULTICLI_SCRATCH/capture.json"
  cat > "$MULTICLI_OVERRIDE_BINARY" <<'PROBE'
#!/usr/bin/env bash
set -euo pipefail
jq -n \
  --arg fixture_home "${FIXTURE_HOME:-}" \
  --arg secret_home "${SECRETCLI_HOME:-}" \
  --arg token "${SECRETCLI_TOKEN:-}" \
  --arg inherited "${GLOBAL_FIXTURE_TOKEN:-}" \
  --arg profile "${MULTICLI_PROFILE_ID:-}" \
  --arg home "${HOME:-}" \
  --arg xdg "${XDG_CONFIG_HOME:-}" \
  '{fixture_home:$fixture_home,secret_home:$secret_home,token:$token,inherited:$inherited,profile:$profile,home:$home,xdg:$xdg}' \
  > "$CAPTURE_OUTPUT"
PROBE
  chmod +x "$MULTICLI_OVERRIDE_BINARY"
  write_file_overlay_adapter
  write_process_secret_adapter
  write_os_user_adapter
  MULTICLI_TEST_TARGETS=()
}

teardown() {
  local target
  for target in ${MULTICLI_TEST_TARGETS[@]+"${MULTICLI_TEST_TARGETS[@]}"}; do
    bash -c 'source "$1"; mc_cred_clear "$2" >/dev/null 2>&1 || true' _ \
      "$MULTICLI_REPO_ROOT/lib/credential-store.sh" "$target"
  done
  unset MULTICLI_TOOLS_DIR MULTICLI_OVERRIDE_BINARY CAPTURE_OUTPUT GLOBAL_FIXTURE_TOKEN COMMAND_CODE_API_KEY
  teardown_scratch
}

write_file_overlay_adapter() {
  cat > "$TOOLS_ROOT/fixture/adapter.json" <<'JSON'
{
  "schemaVersion": 2,
  "id": "fixture",
  "displayName": "Fixture CLI",
  "kind": "cli",
  "binary": { "windows": ["fixture.exe"], "macos": ["fixture"], "linux": ["fixture"] },
  "isolation": {
    "strategy": "accountOverlay",
    "mode": "foreground",
    "env": { "FIXTURE_HOME": "{runtimeRoot}" },
    "clearEnv": ["GLOBAL_FIXTURE_TOKEN"]
  },
  "account": {
    "mechanism": "fileOverlay",
    "credentialFiles": ["auth.json"],
    "credentialPrecedence": ["auth.json"],
    "logoutScope": "profile"
  },
  "normalState": {
    "root": { "windows": "%USERPROFILE%\\.fixture", "macos": "$HOME/.fixture", "linux": "$HOME/.fixture" },
    "sharedPaths": ["config.toml", "agents"],
    "sessionPaths": ["sessions", "history.jsonl"],
    "filePaths": ["config.toml", "history.jsonl"],
    "unsafePaths": []
  },
  "concurrency": { "level": "multiWriter", "singletonScope": "none" },
  "support": {
    "windows": { "level": "supported", "reason": "Fixture only." },
    "macos": { "level": "supported", "reason": "Fixture only." },
    "linux": { "level": "supported", "reason": "Fixture only." }
  },
  "versionCommand": ["--version"]
}
JSON
}

write_process_secret_adapter() {
  cat > "$TOOLS_ROOT/secretcli/adapter.json" <<'JSON'
{
  "schemaVersion": 2,
  "id": "secretcli",
  "displayName": "Secret CLI",
  "kind": "cli",
  "binary": { "windows": ["secretcli.exe"], "macos": ["secretcli"], "linux": ["secretcli"] },
  "isolation": {
    "strategy": "accountOverlay",
    "mode": "foreground",
    "env": { "SECRETCLI_HOME": "{sharedStateRoot}" },
    "clearEnv": []
  },
  "account": {
    "mechanism": "processSecret",
    "credentialFiles": [],
    "credentialPrecedence": ["SECRETCLI_TOKEN"],
    "logoutScope": "process",
    "secret": { "environmentVariable": "SECRETCLI_TOKEN" }
  },
  "normalState": {
    "root": { "windows": "%USERPROFILE%/.secretcli", "macos": "$HOME/.secretcli", "linux": "$HOME/.secretcli" },
    "sharedPaths": ["config.toml"],
    "sessionPaths": ["sessions"],
    "filePaths": ["config.toml"],
    "unsafePaths": []
  },
  "concurrency": { "level": "multiWriter", "singletonScope": "none" },
  "support": {
    "windows": { "level": "supported", "reason": "Fixture only." },
    "macos": { "level": "supported", "reason": "Fixture only." },
    "linux": { "level": "supported", "reason": "Fixture only." }
  },
  "versionCommand": ["--version"]
}
JSON
}

write_os_user_adapter() {
  cat > "$TOOLS_ROOT/lockedcli/adapter.json" <<'JSON'
{
  "schemaVersion": 2,
  "id": "lockedcli",
  "displayName": "Locked CLI",
  "kind": "cli",
  "binary": { "windows": ["lockedcli.exe"], "macos": ["lockedcli"], "linux": ["lockedcli"] },
  "isolation": { "strategy": "accountOverlay", "mode": "foreground", "env": {}, "clearEnv": [] },
  "account": {
    "mechanism": "osUserCredentialStore",
    "credentialFiles": [],
    "credentialPrecedence": ["Fixed OS credential"],
    "logoutScope": "osUser"
  },
  "normalState": {
    "root": { "windows": "%USERPROFILE%/.lockedcli", "macos": "$HOME/.lockedcli", "linux": "$HOME/.lockedcli" },
    "sharedPaths": [],
    "sessionPaths": [],
    "filePaths": [],
    "unsafePaths": []
  },
  "concurrency": { "level": "multiWriter", "singletonScope": "osUser" },
  "support": {
    "windows": { "level": "supported", "reason": "Fixture only." },
    "macos": { "level": "unsupported", "reason": "Fixture only." },
    "linux": { "level": "unsupported", "reason": "Fixture only." }
  },
  "versionCommand": ["--version"]
}
JSON
}

# Track a credential-store target so teardown clears it even on failure.
track_secret_profile() {
  local spec="$1"
  local profile_id
  profile_id="$(jq -r '.profileId' "$MULTICLI_HOME/$spec/.profile.json")"
  MULTICLI_TEST_TARGETS+=("multi-cli/secretcli/$profile_id/SECRETCLI_TOKEN")
}

# --- Flag parsing -------------------------------------------------------------

@test "new --isolated and every alias form create a marked isolated profile" {
  local i=0 flag
  for flag in --isolated --isolate -i; do
    i=$((i + 1))
    run multicli new "fixture/iso-$i" "$flag" --no-seed
    [ "$status" -eq 0 ]
    [ -f "$MULTICLI_HOME/fixture/iso-$i/.isolated" ]
  done
}

@test "new rejects misspelled and undocumented isolated options" {
  local option name
  for option in --isloated -isolate; do
    name="typo-${option//-/}"
    run multicli new "fixture/$name" "$option" --no-seed
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option for new: '$option'"* ]]
    [ ! -e "$MULTICLI_HOME/fixture/$name" ]
  done
}

@test "new --from requires a template name" {
  run multicli new fixture/missing-template --from
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: --from <template>"* ]]
  [ ! -e "$MULTICLI_HOME/fixture/missing-template" ]
}

@test "--shared and --isolated together fail with a clear message and create nothing" {
  run multicli new fixture/clash --shared --isolated --no-seed
  [ "$status" -eq 1 ]
  [[ "$output" == *"--shared"* ]]
  [[ "$output" == *"--isolated"* ]]
  [ ! -e "$MULTICLI_HOME/fixture/clash" ]
}

@test "--isolated refuses schema-v1 adapters with an actionable message" {
  run multicli new codex/legacy-iso --isolated --no-seed
  [ "$status" -eq 1 ]
  [[ "$output" == *"--isolated"* ]]
  [[ "$output" == *"accountOverlay"* ]]
  [ ! -e "$MULTICLI_HOME/codex/legacy-iso" ]
}

@test "a file-overlay isolated profile carries metadata but no overlay skeleton" {
  mkdir -p "$HOME/.fixture"
  printf 'shared-session\n' > "$HOME/.fixture/history.jsonl"

  run multicli new fixture/iso --isolated --no-seed
  [ "$status" -eq 0 ]
  local pdir="$MULTICLI_HOME/fixture/iso"
  [ -f "$pdir/.isolated" ]
  [ "$(jq -r '.schemaVersion' "$pdir/.profile.json")" = "2" ]
  [ "$(jq -r '.adapterId' "$pdir/.profile.json")" = "fixture" ]
  [ "$(jq -r '.mode' "$pdir/.profile.json")" = "isolated" ]
  [[ "$(jq -r '.profileId' "$pdir/.profile.json")" =~ ^[0-9a-fA-F-]{36}$ ]]
  [ ! -e "$pdir/auth" ]
  # no seeding from the native root
  [ ! -e "$pdir/history.jsonl" ]
  [ ! -e "$pdir/config.toml" ]
}

# --- Launch: home env points at the profile dir -------------------------------

@test "isolated launch points the adapter home env at the profile dir, not the shared root or an overlay" {
  mkdir -p "$HOME/.fixture"
  printf 'shared-session\n' > "$HOME/.fixture/history.jsonl"
  run multicli new fixture/iso --isolated --no-seed
  [ "$status" -eq 0 ]
  local pdir="$MULTICLI_HOME/fixture/iso"

  run multicli launch fixture/iso
  [ "$status" -eq 0 ]
  assert_same_path "$(jq -r '.fixture_home' "$CAPTURE_OUTPUT")" "$pdir"
  # no runtime overlay was built
  [ ! -e "$pdir/.runtime" ]
  [ ! -e "$pdir"/.runtime.staging.* ]
}

@test "isolated launch leaves a canary in the native shared root untouched" {
  mkdir -p "$HOME/.fixture"
  printf 'canary\n' > "$HOME/.fixture/canary.txt"
  printf 'shared-session\n' > "$HOME/.fixture/history.jsonl"
  run multicli new fixture/iso --isolated --no-seed
  [ "$status" -eq 0 ]

  run multicli launch fixture/iso
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.fixture/canary.txt" | tr -d '\r')" = "canary" ]
  # the profile holds no links into the shared root
  [ ! -e "$MULTICLI_HOME/fixture/iso/history.jsonl" ]
  [ ! -L "$MULTICLI_HOME/fixture/iso/config.toml" ]
}

@test "isolated launch never creates the native shared root when absent" {
  [ ! -e "$HOME/.fixture" ]
  run multicli new fixture/iso --isolated --no-seed
  [ "$status" -eq 0 ]

  run multicli launch fixture/iso
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.fixture" ]
}

@test "isolated launch still clears inherited account variables" {
  run multicli new fixture/iso --isolated --no-seed
  [ "$status" -eq 0 ]
  export GLOBAL_FIXTURE_TOKEN='wrong-account-secret'

  run multicli launch fixture/iso
  [ "$status" -eq 0 ]
  [ "$(jq -r '.inherited' "$CAPTURE_OUTPUT")" = "" ]
  [ "$GLOBAL_FIXTURE_TOKEN" = "wrong-account-secret" ]
}

@test "Command Code clears its higher-precedence inherited API key" {
  mkdir -p "$TOOLS_ROOT/commandcode"
  cp "$MULTICLI_REPO_ROOT/ai-tools/commandcode/adapter.json" "$TOOLS_ROOT/commandcode/adapter.json"
  run multicli new commandcode/iso --isolated --no-seed
  [ "$status" -eq 0 ]
  export COMMAND_CODE_API_KEY='wrong-account-secret'
  export MULTICLI_OVERRIDE_BINARY="$MULTICLI_SCRATCH/capture-commandcode"
  cat > "$MULTICLI_OVERRIDE_BINARY" <<'PROBE'
#!/usr/bin/env bash
printf '%s' "${COMMAND_CODE_API_KEY:-}" > "$CAPTURE_OUTPUT"
PROBE
  chmod +x "$MULTICLI_OVERRIDE_BINARY"

  run multicli launch commandcode/iso
  [ "$status" -eq 0 ]
  [ ! -s "$CAPTURE_OUTPUT" ]
  [ "$COMMAND_CODE_API_KEY" = "wrong-account-secret" ]
}

@test "isolated launch behaves identically under macOS and Linux platform overrides" {
  run multicli new fixture/iso --isolated --no-seed
  [ "$status" -eq 0 ]
  local pdir="$MULTICLI_HOME/fixture/iso"

  run env MULTICLI_PLATFORM=macos "$MULTICLI_BIN" launch fixture/iso
  [ "$status" -eq 0 ]
  assert_same_path "$(jq -r '.fixture_home' "$CAPTURE_OUTPUT")" "$pdir"
  [ ! -e "$pdir/.runtime" ]

  run env MULTICLI_PLATFORM=linux "$MULTICLI_BIN" launch fixture/iso
  [ "$status" -eq 0 ]
  assert_same_path "$(jq -r '.fixture_home' "$CAPTURE_OUTPUT")" "$pdir"
  [ ! -e "$pdir/.runtime" ]
}

# --- processSecret: home isolation plus per-profile credential ----------------

@test "process-secret isolated profile keeps credential isolation and points home at the profile dir" {
  run multicli new secretcli/account-a --isolated --no-seed
  [ "$status" -eq 0 ]
  run multicli new secretcli/account-b --isolated --no-seed
  [ "$status" -eq 0 ]
  track_secret_profile secretcli/account-a
  track_secret_profile secretcli/account-b
  run bash -c "printf 'token-account-a\n' | '$MULTICLI_BIN' auth set secretcli/account-a"
  [ "$status" -eq 0 ]
  run bash -c "printf 'token-account-b\n' | '$MULTICLI_BIN' auth set secretcli/account-b"
  [ "$status" -eq 0 ]

  run multicli launch secretcli/account-a
  [ "$status" -eq 0 ]
  [ "$(jq -r '.token' "$CAPTURE_OUTPUT")" = "token-account-a" ]
  assert_same_path "$(jq -r '.secret_home' "$CAPTURE_OUTPUT")" "$MULTICLI_HOME/secretcli/account-a"
  [ ! -e "$MULTICLI_HOME/secretcli/account-a/.runtime" ]

  run multicli launch secretcli/account-b
  [ "$status" -eq 0 ]
  [ "$(jq -r '.token' "$CAPTURE_OUTPUT")" = "token-account-b" ]
  assert_same_path "$(jq -r '.secret_home' "$CAPTURE_OUTPUT")" "$MULTICLI_HOME/secretcli/account-b"
  # the native shared root was never touched
  [ ! -e "$HOME/.secretcli" ]
}

@test "process-secret isolated launch without a stored credential fails closed with the auth hint" {
  run multicli new secretcli/account-a --isolated --no-seed
  [ "$status" -eq 0 ]

  run multicli launch secretcli/account-a
  [ "$status" -eq 1 ]
  [[ "$output" == *"multi-cli auth set secretcli/account-a"* ]]
}

# --- fixed OS credential identity ---------------------------------------------

@test "isolated mode is rejected for OS credential-store adapters before profile creation" {
  run multicli new lockedcli/iso --isolated --no-seed
  [ "$status" -eq 1 ]
  [[ "$output" == *"folder redirection does not isolate the OS credential store"* ]]
  [ ! -e "$MULTICLI_HOME/lockedcli/iso" ]
}

@test "a legacy isolated marker cannot bypass the OS credential-store boundary" {
  run multicli new lockedcli/legacy --no-seed
  [ "$status" -eq 0 ]
  touch "$MULTICLI_HOME/lockedcli/legacy/.isolated"

  run env MULTICLI_PLATFORM=windows "$MULTICLI_BIN" launch lockedcli/legacy
  [ "$status" -eq 1 ]
  [[ "$output" == *"folder redirection does not isolate the OS credential store"* ]]
  [ ! -e "$CAPTURE_OUTPUT" ]
}

# --- list / continue ----------------------------------------------------------

@test "list shows isolated profiles as isolated" {
  run multicli new fixture/iso --isolated --no-seed
  [ "$status" -eq 0 ]
  run multicli new fixture/plain --no-seed
  [ "$status" -eq 0 ]

  run multicli list fixture
  [ "$status" -eq 0 ]
  [[ "$output" == *"iso"* ]]
  run bash -c "'$MULTICLI_BIN' list fixture | grep -E '^\\s+iso\\s'"
  [[ "$output" == *"isolated"* ]]
  run bash -c "'$MULTICLI_BIN' list fixture | grep -E '^\\s+plain\\s'"
  [[ "$output" != *"isolated"* ]]
}

@test "continue copies sessions between isolated profiles, never credentials" {
  run multicli new fixture/iso-a --isolated --no-seed
  [ "$status" -eq 0 ]
  run multicli new fixture/iso-b --isolated --no-seed
  [ "$status" -eq 0 ]
  local src="$MULTICLI_HOME/fixture/iso-a"
  local dst="$MULTICLI_HOME/fixture/iso-b"
  mkdir -p "$src/sessions/2026/06/11"
  printf '%s\n' '{"type":"session_meta","payload":{"id":"abc-123"}}' \
    > "$src/sessions/2026/06/11/rollout-2026-06-11T10-00-00-abc-123.jsonl"
  printf '%s\n' '{"session":"abc-123","text":"fix the build"}' > "$src/history.jsonl"
  printf '%s\n' '{"token":"sk-secret"}' > "$src/auth.json"
  printf '%s\n' '{"token":"sk-decoy"}' > "$src/sessions/auth.json"

  run multicli continue fixture iso-a iso-b
  [ "$status" -eq 0 ]
  [ -f "$dst/sessions/2026/06/11/rollout-2026-06-11T10-00-00-abc-123.jsonl" ]
  [ -f "$dst/history.jsonl" ]
  [ ! -e "$dst/auth.json" ]
  [ ! -e "$dst/sessions/auth.json" ]
}

@test "continue from base into an isolated profile copies the native root's sessions" {
  mkdir -p "$HOME/.fixture/sessions/2026/06/11"
  printf '%s\n' '{"type":"session_meta","payload":{"id":"base-1"}}' \
    > "$HOME/.fixture/sessions/2026/06/11/rollout-2026-06-11T10-00-00-base-1.jsonl"
  printf 'shared-history\n' > "$HOME/.fixture/history.jsonl"
  printf '%s\n' '{"token":"sk-base"}' > "$HOME/.fixture/auth.json"
  run multicli new fixture/iso --isolated --no-seed
  [ "$status" -eq 0 ]

  run multicli continue fixture base iso
  [ "$status" -eq 0 ]
  local dst="$MULTICLI_HOME/fixture/iso"
  [ -f "$dst/sessions/2026/06/11/rollout-2026-06-11T10-00-00-base-1.jsonl" ]
  [ -f "$dst/history.jsonl" ]
  [ ! -e "$dst/auth.json" ]
}

@test "continue between shared (non-isolated) schema-v2 profiles stays a no-op" {
  run multicli new fixture/account-a --no-seed
  [ "$status" -eq 0 ]
  run multicli new fixture/account-b --no-seed
  [ "$status" -eq 0 ]

  run multicli continue fixture account-a account-b
  [ "$status" -eq 0 ]
  [[ "$output" == *"already share conversations"* ]]
}

@test "continue refuses a missing shared schema-v2 endpoint" {
  run multicli new fixture/account-a --no-seed
  [ "$status" -eq 0 ]

  run multicli continue fixture account-a missing

  [ "$status" -eq 1 ]
  [[ "$output" == *"Destination endpoint 'missing' not found"* ]]
}

@test "isolated mode never overrides an unsupported platform" {
  jq '.support.windows={"level":"unsupported","reason":"No Windows product."} | .support.macos={"level":"unsupported","reason":"No macOS product."} | .support.linux={"level":"unsupported","reason":"No Linux product."}' \
    "$TOOLS_ROOT/fixture/adapter.json" > "$TOOLS_ROOT/fixture/updated.json"
  mv "$TOOLS_ROOT/fixture/updated.json" "$TOOLS_ROOT/fixture/adapter.json"

  run multicli new fixture/account-a --isolated --no-seed
  [ "$status" -eq 0 ]

  run multicli launch fixture/account-a

  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported"* ]]
  [[ "$output" == *"No "*" product."* ]]
  [ ! -e "$CAPTURE_OUTPUT" ]
}

@test "isolated lifecycle honors normalState.runtimeSubdir" {
  jq '.normalState.runtimeSubdir="state"' "$TOOLS_ROOT/fixture/adapter.json" > "$TOOLS_ROOT/fixture/updated.json"
  mv "$TOOLS_ROOT/fixture/updated.json" "$TOOLS_ROOT/fixture/adapter.json"
  run multicli new fixture/iso-a --isolated --no-seed
  [ "$status" -eq 0 ]
  run multicli new fixture/iso-b --isolated --no-seed
  [ "$status" -eq 0 ]
  local source="$MULTICLI_HOME/fixture/iso-a"
  mkdir -p "$source/state/sessions"
  printf 'nested-session\n' > "$source/state/sessions/chat.jsonl"
  printf 'nested-config\n' > "$source/state/config.toml"
  mkdir -p "$source/sessions"
  printf 'wrong-root\n' > "$source/sessions/decoy.jsonl"

  run multicli continue fixture iso-a iso-b
  [ "$status" -eq 0 ]
  [ "$(cat "$MULTICLI_HOME/fixture/iso-b/state/sessions/chat.jsonl" | tr -d '\r')" = nested-session ]
  [ ! -e "$MULTICLI_HOME/fixture/iso-b/sessions/decoy.jsonl" ]

  run multicli clone fixture/iso-a fixture/iso-clone
  [ "$status" -eq 0 ]
  [ "$(cat "$MULTICLI_HOME/fixture/iso-clone/state/config.toml" | tr -d '\r')" = nested-config ]
  [ "$(cat "$MULTICLI_HOME/fixture/iso-clone/state/sessions/chat.jsonl" | tr -d '\r')" = nested-session ]
  [ ! -e "$MULTICLI_HOME/fixture/iso-clone/sessions/decoy.jsonl" ]
}

@test "clone creates a fresh schema-v2 identity without credentials or runtime" {
  run multicli new fixture/iso-a --isolated --no-seed
  [ "$status" -eq 0 ]
  local source="$MULTICLI_HOME/fixture/iso-a"
  printf 'isolated-config\n' > "$source/config.toml"
  printf 'credential-must-not-copy\n' > "$source/auth.json"
  mkdir -p "$source/.runtime"
  printf 'runtime-must-not-copy\n' > "$source/.runtime/rogue.txt"
  local source_id
  source_id="$(jq -r '.profileId' "$source/.profile.json")"

  run multicli clone fixture/iso-a fixture/iso-b

  [ "$status" -eq 0 ]
  local destination="$MULTICLI_HOME/fixture/iso-b"
  [ -f "$destination/.isolated" ]
  [ "$(jq -r '.mode' "$destination/.profile.json")" = isolated ]
  [ "$(jq -r '.profileId' "$destination/.profile.json")" != "$source_id" ]
  [ "$(cat "$destination/config.toml" | tr -d '\r')" = isolated-config ]
  [ ! -e "$destination/auth.json" ]
  [ ! -e "$destination/.runtime" ]
}
