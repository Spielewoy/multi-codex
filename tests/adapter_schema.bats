#!/usr/bin/env bats

load helpers/common

setup() {
  setup_scratch
  TOOLS_ROOT="$MULTICLI_SCRATCH/schema-tools"
  mkdir -p "$TOOLS_ROOT"
  VALIDATOR="$MULTICLI_REPO_ROOT/scripts/validate-adapters.sh"
}

teardown() {
  teardown_scratch
}

write_adapter() {
  local dir_name="$1" json="$2"
  mkdir -p "$TOOLS_ROOT/$dir_name"
  printf '%s\n' "$json" > "$TOOLS_ROOT/$dir_name/adapter.json"
}

valid_v2_adapter() {
  cat <<'JSON'
{
  "schemaVersion": 2,
  "id": "test-cli",
  "displayName": "Test CLI",
  "kind": "cli",
  "binary": {
    "windows": ["test-cli.exe"],
    "macos": ["test-cli"],
    "linux": ["test-cli"]
  },
  "isolation": {
    "strategy": "accountOverlay",
    "mode": "foreground",
    "env": { "TEST_HOME": "{runtimeRoot}" },
    "clearEnv": ["GLOBAL_TEST_TOKEN"]
  },
  "account": {
    "mechanism": "fileOverlay",
    "credentialFiles": ["auth.json"],
    "credentialPrecedence": ["auth.json"],
    "logoutScope": "profile"
  },
  "normalState": {
    "root": {
      "windows": "%USERPROFILE%\\.test-cli",
      "macos": "$HOME/.test-cli",
      "linux": "$HOME/.test-cli"
    },
    "sharedPaths": ["config.toml", "agents", "skills"],
    "sessionPaths": ["sessions", "history.jsonl"],
    "unsafePaths": ["cache/account.sqlite"]
  },
  "concurrency": {
    "level": "multiWriter",
    "singletonScope": "none"
  },
  "support": {
    "windows": { "level": "supported", "reason": "File overlay with profile-local auth.json." },
    "macos": { "level": "supported" },
    "linux": { "level": "supported" }
  },
  "install": "https://example.test/install",
  "versionCommand": ["--version"]
}
JSON
}

@test "validator accepts existing schema-v1 adapters for legacy compatibility" {
  write_adapter legacy '{"id":"legacy","displayName":"Legacy","kind":"cli","binary":{"windows":["legacy.exe"],"macos":["legacy"],"linux":["legacy"]},"isolation":{"strategy":"env","env":{"LEGACY_HOME":"{profileDir}"}},"share":{"systemHome":"$HOME/.legacy","linkable":["config"],"neverLink":["auth.json"]},"session":{"portable":true,"paths":["sessions"],"credentials":["auth.json"]},"status":"stable"}'

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Validated 1 adapter(s)"* ]]
}

@test "validator accepts a complete schema-v2 account overlay" {
  write_adapter test-cli "$(valid_v2_adapter)"

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Validated 1 adapter(s)"* ]]
}

@test "JSON schema accepts the runtime subdirectory used by Command Code" {
  run jq -e '
    .properties.normalState.properties.runtimeSubdir["$ref"] == "#/$defs/relativePath"
  ' "$MULTICLI_REPO_ROOT/schema/adapter.schema.json"

  [ "$status" -eq 0 ]
}

@test "Windows Bash resolves only AppX OS-user adapters" {
  local stub_bin="$MULTICLI_SCRATCH/bin"
  mkdir -p "$stub_bin" "$TOOLS_ROOT/codex-gui"
  cp "$MULTICLI_REPO_ROOT/codex-gui/adapter.json" "$TOOLS_ROOT/codex-gui/adapter.json"
  printf '#!/usr/bin/env bash\nprintf "appx:FixtureFamily!App\\n"\n' > "$stub_bin/powershell.exe"
  chmod +x "$stub_bin/powershell.exe"

  run env PATH="$stub_bin:$PATH" MULTICLI_PLATFORM=windows MULTICLI_TOOLS_DIR="$TOOLS_ROOT" \
    bash -c 'multicli_bin="$1"; set -- help; source "$multicli_bin" >/dev/null; find_adapter_binary codex-gui' _ "$MULTICLI_BIN"

  [ "$status" -eq 0 ]
  [ "$output" = "appx:FixtureFamily!App" ]

  jq '.account.mechanism = "fileOverlay"' "$TOOLS_ROOT/codex-gui/adapter.json" \
    > "$TOOLS_ROOT/codex-gui/adapter.tmp"
  mv "$TOOLS_ROOT/codex-gui/adapter.tmp" "$TOOLS_ROOT/codex-gui/adapter.json"

  run env PATH="$stub_bin:$PATH" MULTICLI_PLATFORM=windows MULTICLI_TOOLS_DIR="$TOOLS_ROOT" \
    bash -c 'multicli_bin="$1"; set -- help; source "$multicli_bin" >/dev/null; find_adapter_binary codex-gui' _ "$MULTICLI_BIN"

  [ "$status" -ne 0 ]

  jq '.account.mechanism = "osUserCredentialStore" | .binary.windows = ["uri:codex"]' \
    "$TOOLS_ROOT/codex-gui/adapter.json" > "$TOOLS_ROOT/codex-gui/adapter.tmp"
  mv "$TOOLS_ROOT/codex-gui/adapter.tmp" "$TOOLS_ROOT/codex-gui/adapter.json"

  run env PATH="$stub_bin:$PATH" MULTICLI_PLATFORM=windows MULTICLI_TOOLS_DIR="$TOOLS_ROOT" \
    bash -c 'multicli_bin="$1"; set -- help; source "$multicli_bin" >/dev/null; find_adapter_binary codex-gui' _ "$MULTICLI_BIN"

  [ "$status" -ne 0 ]
}

@test "validator rejects malformed JSON with the adapter path" {
  write_adapter broken '{"id":"broken"'

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"broken/adapter.json: invalid JSON"* ]]
}

@test "validator rejects a directory and adapter id mismatch" {
  write_adapter wrong-dir "$(valid_v2_adapter)"

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"directory 'wrong-dir' does not match id 'test-cli'"* ]]
}

@test "validator rejects unsafe adapter ids" {
  write_adapter 'bad id' '{"schemaVersion":2,"id":"bad id","displayName":"Bad","kind":"cli","binary":{"windows":["bad"],"macos":["bad"],"linux":["bad"]},"isolation":{"strategy":"accountOverlay","mode":"foreground"},"account":{"mechanism":"inseparable","reason":"combined state"},"normalState":{"root":{"windows":"x","macos":"x","linux":"x"},"sharedPaths":[],"sessionPaths":[],"unsafePaths":[]},"concurrency":{"level":"unsupported","singletonScope":"user"},"support":{"windows":{"level":"unsupported","reason":"combined state"},"macos":{"level":"unsupported","reason":"combined state"},"linux":{"level":"unsupported","reason":"combined state"}}}'

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"id must match"* ]]
}

@test "validator rejects schema-v2 darwin binary keys" {
  local adapter
  adapter="$(valid_v2_adapter | jq 'del(.binary.macos) | .binary.darwin=["test-cli"]')"
  write_adapter test-cli "$adapter"

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"binary uses unsupported platform key 'darwin'; use 'macos'"* ]]
}

@test "validator rejects credential paths overlapping normal state" {
  local adapter
  adapter="$(valid_v2_adapter | jq '.account.credentialFiles=["sessions/auth.json"] | .normalState.sessionPaths=["sessions"]')"
  write_adapter test-cli "$adapter"

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"credential path 'sessions/auth.json' overlaps session path 'sessions'"* ]]
}

@test "validator rejects parent traversal in declared state paths" {
  local adapter
  adapter="$(valid_v2_adapter | jq '.normalState.sharedPaths=["../outside"]')"
  write_adapter test-cli "$adapter"

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"shared path '../outside' must be a safe relative path"* ]]
}

@test "validator rejects unknown placeholders" {
  local adapter
  adapter="$(valid_v2_adapter | jq '.isolation.env.TEST_HOME="{mysteryRoot}"')"
  write_adapter test-cli "$adapter"

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown placeholder '{mysteryRoot}'"* ]]
}

@test "validator requires a reason for unsupported support" {
  local adapter
  adapter="$(valid_v2_adapter | jq '.support.windows={"level":"unsupported"}')"
  write_adapter test-cli "$adapter"

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"support.windows.reason is required for level 'unsupported'"* ]]
}

@test "validator accepts supported support without a reason" {
  local adapter
  adapter="$(valid_v2_adapter | jq 'del(.support.windows.reason)')"
  write_adapter test-cli "$adapter"

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Validated 1 adapter(s)"* ]]
}

@test "validator rejects the retired experimental level with a clear message" {
  local adapter
  adapter="$(valid_v2_adapter | jq '.support.windows={"level":"experimental","reason":"legacy"}')"
  write_adapter test-cli "$adapter"

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"support.windows.level 'experimental' was retired; use 'supported' or 'unsupported'"* ]]
}

@test "validator rejects retired evidenceId metadata" {
  local adapter
  adapter="$(valid_v2_adapter | jq '.evidenceId="EV-1"')"
  write_adapter test-cli "$adapter"

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported top-level field 'evidenceId'"* ]]
}

@test "validator rejects unknown nested fields" {
  local adapter
  adapter="$(valid_v2_adapter | jq '.support.windows.note="not part of the contract"')"
  write_adapter test-cli "$adapter"

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported field 'support.windows.note'"* ]]
}

@test "validator rejects legacy fields in schema-v2" {
  local adapter
  adapter="$(valid_v2_adapter | jq '.status="stable"')"
  write_adapter test-cli "$adapter"

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported top-level field 'status'"* ]]
}

@test "validator rejects unknown schema-v1 nested fields" {
  write_adapter legacy '{"id":"legacy","displayName":"Legacy","kind":"cli","binary":{"windows":["legacy"],"macos":["legacy"],"linux":["legacy"]},"isolation":{"strategy":"env","env":{"HOME":"{profileDir}"}},"share":{"systemHome":"$HOME/.legacy","linkable":["config"],"neverLink":["auth.json"],"note":"extra"},"status":"stable"}'

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported field 'share.note'"* ]]
}

@test "validator rejects v1 linkable and neverLink overlap" {
  write_adapter legacy '{"id":"legacy","displayName":"Legacy","kind":"cli","binary":{"windows":["legacy"],"macos":["legacy"],"linux":["legacy"]},"isolation":{"strategy":"env","env":{"HOME":"{profileDir}"}},"share":{"systemHome":"$HOME/.legacy","linkable":["auth.json"],"neverLink":["auth.json"]},"status":"stable"}'

  run bash "$VALIDATOR" "$TOOLS_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"share.linkable path 'auth.json' overlaps share.neverLink path 'auth.json'"* ]]
}

@test "platform normalization matches schema binary keys" {
  run bash -c "set -- help; source '$MULTICLI_BIN' >/dev/null 2>&1; MULTICLI_PLATFORM=darwin platform"
  [ "$status" -eq 0 ]
  [ "$output" = "macos" ]

  run bash -c "set -- help; source '$MULTICLI_BIN' >/dev/null 2>&1; MULTICLI_PLATFORM=windows platform"
  [ "$status" -eq 0 ]
  [ "$output" = "windows" ]
}
