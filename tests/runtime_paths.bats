#!/usr/bin/env bats

load helpers/common

setup() {
  setup_scratch
  export PATH="/usr/bin:$PATH"
  mkdir -p "$MULTICLI_HOME/codex/demo"
}

teardown() {
  teardown_scratch
}

@test "storage_canonical preserves missing suffixes beneath the nearest real ancestor" {
  local real_root="$MULTICLI_HOME/state/live"
  mkdir -p "$real_root"

  run env MULTICLI_HOME="$MULTICLI_HOME" MULTICLI_TOOLS_DIR="$MULTICLI_TOOLS_DIR" \
    bash -c 'multicli_bin="$1"; target="$2"; set -- help; source "$multicli_bin" >/dev/null; storage_canonical "$target"' _ \
    "$MULTICLI_BIN" "$real_root/missing/leaf"

  [ "$status" -eq 0 ]
  assert_same_path "$output" "$real_root/missing/leaf"
}

@test "find_adapter_binary skips an unresolved AppX candidate and keeps searching" {
  local stub_bin="$MULTICLI_SCRATCH/bin"
  mkdir -p "$stub_bin" "$MULTICLI_TOOLS_DIR/appx-tool"
  cat > "$MULTICLI_TOOLS_DIR/appx-tool/adapter.json" <<'JSON'
{"schemaVersion":2,"id":"appx-tool","binary":{"windows":["appx:Missing.Package!App","fallback-tool.exe"]},"isolation":{"strategy":"accountOverlay"},"account":{"mechanism":"osUserCredentialStore"}}
JSON
  printf '#!/usr/bin/env bash\nexit 1\n' > "$stub_bin/powershell.exe"
  printf '#!/usr/bin/env bash\nprintf "fallback\\n"\n' > "$stub_bin/fallback-tool.exe"
  chmod +x "$stub_bin/powershell.exe" "$stub_bin/fallback-tool.exe"

  run env PATH="$stub_bin:$PATH" MULTICLI_PLATFORM=windows MULTICLI_TOOLS_DIR="$MULTICLI_TOOLS_DIR" \
    bash -c 'multicli_bin="$1"; set -- help; source "$multicli_bin" >/dev/null; find_adapter_binary appx-tool' _ "$MULTICLI_BIN"

  [ "$status" -eq 0 ]
  [ "$output" = "$stub_bin/fallback-tool.exe" ]
}

@test "launch_sandbox_user announces first launch before Linux provisioning" {
  run env MULTICLI_PLATFORM=linux MULTICLI_TOOLS_DIR="$MULTICLI_TOOLS_DIR" \
    bash -c '
      multicli_bin="$1"; profile_dir="$2"; set -- help; source "$multicli_bin" >/dev/null
      id() { [ "$1" = "-u" ] && { printf "123\n"; return 0; }; return 1; }
      create_sandbox_user() { printf "created:%s:%s\n" "$1" "$2"; }
      sudo() { printf "sudo:%s\n" "$*"; }
      xhost() { return 0; }
      launch_sandbox_user codex "$profile_dir" /usr/bin/true
    ' _ "$MULTICLI_BIN" "$MULTICLI_HOME/codex/demo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"First launch: creating sandbox user (requires sudo)..."* ]]
  [[ "$output" == *"created:demo:$MULTICLI_HOME/codex/demo"* ]]
}

@test "launch_sandbox_user announces first launch before macOS provisioning" {
  run env MULTICLI_PLATFORM=macos MULTICLI_TOOLS_DIR="$MULTICLI_TOOLS_DIR" \
    bash -c '
      multicli_bin="$1"; profile_dir="$2"; set -- help; source "$multicli_bin" >/dev/null
      dscl() { return 1; }
      create_sandbox_user() { printf "created:%s:%s\n" "$1" "$2"; }
      sudo() { printf "sudo:%s\n" "$*"; }
      launch_sandbox_user codex "$profile_dir" /usr/bin/true
    ' _ "$MULTICLI_BIN" "$MULTICLI_HOME/codex/demo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"First launch: creating sandbox user (requires sudo)..."* ]]
  [[ "$output" == *"created:demo:$MULTICLI_HOME/codex/demo"* ]]
}
