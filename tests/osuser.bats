#!/usr/bin/env bats
# Real-execution tests for lib/multicli-osuser.sh -- the osUserCredentialStore
# account mechanism (bash side; PowerShell mirror: lib/MultiCli.OsUser.psm1,
# tested in tests/OsUser.Tests.ps1).
#
# No mocks. On this non-elevated Windows host the suite really proves:
#   - username derivation (fixed SHA-256 vector, determinism, collisions,
#     length) including bash/PowerShell parity through real powershell.exe;
#   - ownership record read + refuse-foreign logic against real .osuser.json
#     files;
#   - the elevation gate fires BEFORE any provisioning (verified with a real
#     `net user` probe that nothing was created);
#   - macOS/Linux fail with the precise fail-closed message.
# Bats `skip` is used only where the behavior genuinely cannot fire (elevated
# host, non-Windows host), never for testable behavior.

load helpers/common

export OSUSER_LIB="$MULTICLI_REPO_ROOT/lib/multicli-osuser.sh"
export OSUSER_PSM1="$MULTICLI_REPO_ROOT/lib/MultiCli.OsUser.psm1"

FIXTURE_PROFILE_ID="11111111-2222-3333-4444-555555555555"
# sha256("agy-cli:11111111-2222-3333-4444-555555555555") = fcfb4582f558...
FIXTURE_USERNAME="mcli_fcfb4582f558"

setup() {
  setup_scratch
  export USERPROFILE="$HOME"
  export APPDATA="$HOME/AppData/Roaming"
  export LOCALAPPDATA="$HOME/AppData/Local"
  # The REAL agy-cli adapter (osUserCredentialStore, foreground, sharedPaths).
  FIXTURE_ADAPTER="$MULTICLI_SCRATCH/tools/agy-cli"
  mkdir -p "$FIXTURE_ADAPTER"
  cp "$MULTICLI_REPO_ROOT/ai-tools/agy-cli/adapter.json" "$FIXTURE_ADAPTER/adapter.json"
  FIXTURE_PROFILE_DIR="$MULTICLI_HOME/agy-cli/work"
  mkdir -p "$FIXTURE_PROFILE_DIR"
  jq -n --arg id "$FIXTURE_PROFILE_ID" \
    '{schemaVersion:2,adapterId:"agy-cli",profileId:$id,mode:"accountOverlay"}' \
    > "$FIXTURE_PROFILE_DIR/.profile.json"
}

teardown() {
  teardown_scratch
}

# Run one library function in a fresh shell with only the library sourced.
osuser_call() {
  bash -c '
    source "$OSUSER_LIB"
    "$@"
  ' _ "$@"
}

# Same as osuser_call, but forces the platform selector.
osuser_platform_call() {
  local plat="$1"
  shift
  MULTICLI_PLATFORM="$plat" osuser_call "$@"
}

# Write an .osuser.json ownership record for the fixture profile with $1 as
# the recorded username (matching or foreign, depending on the test).
write_ownership() {
  jq -n --arg tool "agy-cli" --arg pid "$FIXTURE_PROFILE_ID" --arg user "$1" \
    '{schemaVersion:1,tool:$tool,profileId:$pid,username:$user,taskName:("multi-cli-" + ($user|ltrimstr("mcli_"))),credentialTarget:("multi-cli/osuser/" + $user),createdUtc:"2026-07-20T00:00:00.0000000Z"}' \
    > "$FIXTURE_PROFILE_DIR/.osuser.json"
}

is_elevated() {
  net session >/dev/null 2>&1
}

# --- Identity derivation ----------------------------------------------------

@test "username derivation matches the fixed SHA-256 vector and is deterministic" {
  run osuser_call mc_osuser_username agy-cli "$FIXTURE_PROFILE_ID"
  [ "$status" -eq 0 ]
  [ "$output" = "$FIXTURE_USERNAME" ]
  run osuser_call mc_osuser_username agy-cli "$FIXTURE_PROFILE_ID"
  [ "$status" -eq 0 ]
  [ "$output" = "$FIXTURE_USERNAME" ]
}

@test "username fits the 20-char Windows SAM limit and uses lowercase hex" {
  run osuser_call mc_osuser_username kiro "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 17 ]
  [[ "$output" =~ ^mcli_[0-9a-f]{12}$ ]]
}

@test "usernames are collision-safe across every osUser adapter and across profiles" {
  local names=() tool unique
  for tool in antigravity agy-cli kiro zed windsurf copilot-vscode cursor; do
    names+=("$(osuser_call mc_osuser_username "$tool" "$FIXTURE_PROFILE_ID")")
  done
  unique="$(printf '%s\n' "${names[@]}" | sort -u | wc -l | tr -d ' ')"
  [ "$unique" = "7" ]
  [ "$(osuser_call mc_osuser_username agy-cli 99999999-8888-7777-6666-555555555555)" != "$FIXTURE_USERNAME" ]
}

@test "tool id case does not change the derived username" {
  [ "$(osuser_call mc_osuser_username AGY-CLI "$FIXTURE_PROFILE_ID")" = "$FIXTURE_USERNAME" ]
}

@test "bash and PowerShell derive identical usernames" {
  command -v powershell.exe >/dev/null 2>&1 || skip "powershell.exe not available"
  local ps_name
  ps_name="$(powershell.exe -NoProfile -Command "Import-Module '$(cygpath -w "$OSUSER_PSM1")' -Force; Get-OsUserName -Tool kiro -ProfileId $FIXTURE_PROFILE_ID" | tr -d '\r\n')"
  [ "$ps_name" = "$(osuser_call mc_osuser_username kiro "$FIXTURE_PROFILE_ID")" ]
}

@test "task name and credential target formats" {
  [ "$(osuser_call mc_osuser_task_name "$FIXTURE_USERNAME")" = "multi-cli-fcfb4582f558" ]
  [ "$(osuser_call mc_osuser_cred_target "$FIXTURE_USERNAME")" = "multi-cli/osuser/$FIXTURE_USERNAME" ]
}

@test "derivation rejects a missing tool id or profileId" {
  run osuser_call mc_osuser_username "" "$FIXTURE_PROFILE_ID"
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires a tool id"* ]]
  run osuser_call mc_osuser_username agy-cli ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires a profileId"* ]]
}

# --- Ownership records --------------------------------------------------------

@test "ownership fields round-trip; a missing record yields exit 1 and no output" {
  write_ownership "$FIXTURE_USERNAME"
  [ "$(osuser_call mc_osuser_ownership_field "$FIXTURE_PROFILE_DIR" .username)" = "$FIXTURE_USERNAME" ]
  [ "$(osuser_call mc_osuser_ownership_field "$FIXTURE_PROFILE_DIR" .tool)" = "agy-cli" ]
  run osuser_call mc_osuser_ownership_field "$MULTICLI_HOME" .username
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "is_owned reflects the record file" {
  run osuser_call mc_osuser_is_owned "$FIXTURE_PROFILE_DIR"
  [ "$status" -eq 1 ]
  write_ownership "$FIXTURE_USERNAME"
  run osuser_call mc_osuser_is_owned "$FIXTURE_PROFILE_DIR"
  [ "$status" -eq 0 ]
}

@test "a consistent ownership record passes verification" {
  write_ownership "$FIXTURE_USERNAME"
  run osuser_call mc_osuser_assert_ownership "$FIXTURE_PROFILE_DIR"
  [ "$status" -eq 0 ]
}

@test "an internally valid ownership record copied from another profile is refused" {
  local other_profile="$MULTICLI_HOME/agy-cli/other"
  local other_id="99999999-8888-7777-6666-555555555555"
  local other_username
  other_username="$(osuser_call mc_osuser_username agy-cli "$other_id")"
  jq -n --arg tool agy-cli --arg pid "$other_id" --arg user "$other_username" \
    '{schemaVersion:1,tool:$tool,profileId:$pid,username:$user,taskName:("multi-cli-" + ($user|ltrimstr("mcli_"))),credentialTarget:("multi-cli/osuser/" + $user),createdUtc:"2026-07-20T00:00:00Z"}' \
    > "$FIXTURE_PROFILE_DIR/.osuser.json"

  run osuser_call mc_osuser_assert_ownership "$FIXTURE_PROFILE_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"belongs to another profile"* ]]
  [ -f "$FIXTURE_PROFILE_DIR/.osuser.json" ]
  [ ! -e "$other_profile" ]
}

@test "a valid username with tampered task or credential coordinates is refused" {
  write_ownership "$FIXTURE_USERNAME"
  jq '.taskName="unrelated-task"' "$FIXTURE_PROFILE_DIR/.osuser.json" > "$FIXTURE_PROFILE_DIR/.osuser.tmp"
  mv "$FIXTURE_PROFILE_DIR/.osuser.tmp" "$FIXTURE_PROFILE_DIR/.osuser.json"
  run osuser_call mc_osuser_assert_ownership "$FIXTURE_PROFILE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match the derived identity"* ]]

  write_ownership "$FIXTURE_USERNAME"
  jq '.credentialTarget="unrelated/credential"' "$FIXTURE_PROFILE_DIR/.osuser.json" > "$FIXTURE_PROFILE_DIR/.osuser.tmp"
  mv "$FIXTURE_PROFILE_DIR/.osuser.tmp" "$FIXTURE_PROFILE_DIR/.osuser.json"
  run osuser_call mc_osuser_assert_ownership "$FIXTURE_PROFILE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match the derived identity"* ]]
}

@test "a fabricated foreign ownership record is refused and left in place" {
  write_ownership "mcli_deadbeef0000"
  run osuser_call mc_osuser_assert_ownership "$FIXTURE_PROFILE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Refusing to touch OS user 'mcli_deadbeef0000'"* ]]
  [[ "$output" == *"does not match the derived identity '$FIXTURE_USERNAME'"* ]]
  [[ "$output" == *"not multi-cli-owned"* ]]
  [ -f "$FIXTURE_PROFILE_DIR/.osuser.json" ]
}

# --- macOS / Linux provisioning contract -------------------------------------

@test "macOS provisioning fails before mutation when a required command is unavailable" {
  run env MULTICLI_PLATFORM=macos bash -c '
    function command() {
      if [ "$1" = -v ] && [ "$2" = sudo ]; then return 1; fi
      builtin command "$@"
    }
    source "$OSUSER_LIB"
    mc_osuser_ensure agy-cli "$1" "$2"
  ' _ "$FIXTURE_PROFILE_DIR" "$FIXTURE_ADAPTER/adapter.json"

  [ "$status" -ne 0 ]
  [[ "$output" == *"requires 'sudo'"* ]]
  [ ! -f "$FIXTURE_PROFILE_DIR/.osuser.json" ]
  ! id "$FIXTURE_USERNAME" >/dev/null 2>&1
}

@test "Linux provisioning fails before mutation when a required command is unavailable" {
  run env MULTICLI_PLATFORM=linux bash -c '
    function command() {
      if [ "$1" = -v ] && [ "$2" = sudo ]; then return 1; fi
      builtin command "$@"
    }
    source "$OSUSER_LIB"
    mc_osuser_ensure agy-cli "$1" "$2"
  ' _ "$FIXTURE_PROFILE_DIR" "$FIXTURE_ADAPTER/adapter.json"

  [ "$status" -ne 0 ]
  [[ "$output" == *"requires 'sudo'"* ]]
  [ ! -f "$FIXTURE_PROFILE_DIR/.osuser.json" ]
  ! id "$FIXTURE_USERNAME" >/dev/null 2>&1
}

@test "launch without a POSIX ownership record fails before starting the binary" {
  run env MC_OSUSER_ADAPTER_PATH="$FIXTURE_ADAPTER/adapter.json" MULTICLI_PLATFORM=macos \
    bash -c 'source "$OSUSER_LIB"; mc_osuser_launch agy-cli "$1" /usr/bin/true' _ "$FIXTURE_PROFILE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"has no OS-user ownership record"* ]]
}

@test "remove with no record is a no-op on every platform (profile delete safety)" {
  run osuser_call mc_osuser_remove "$FIXTURE_PROFILE_DIR"
  [ "$status" -eq 0 ]
  run osuser_platform_call macos mc_osuser_remove "$FIXTURE_PROFILE_DIR"
  [ "$status" -eq 0 ]
  run osuser_platform_call linux mc_osuser_remove "$FIXTURE_PROFILE_DIR"
  [ "$status" -eq 0 ]
}

@test "remove refuses a fabricated foreign record before any deletion" {
  write_ownership "mcli_deadbeef0000"
  run osuser_call mc_osuser_remove "$FIXTURE_PROFILE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Refusing to touch OS user 'mcli_deadbeef0000'"* ]]
  [ -f "$FIXTURE_PROFILE_DIR/.osuser.json" ]
}

# --- Windows elevation gate (non-admin host) -----------------------------------

@test "ensure on Windows without elevation fails precisely BEFORE creating anything" {
  _multicli_is_windows || skip "requires Windows"
  if is_elevated; then skip "host is elevated; the elevation gate cannot fire"; fi
  run osuser_call mc_osuser_ensure agy-cli "$FIXTURE_PROFILE_DIR" "$FIXTURE_ADAPTER/adapter.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OS-user isolation for agy-cli/work requires an elevated terminal (Run as Administrator)."* ]]
  # Proof nothing was created: the derived user does not exist and no
  # ownership record was written.
  run net user "$FIXTURE_USERNAME"
  [ "$status" -ne 0 ]
  [ ! -f "$FIXTURE_PROFILE_DIR/.osuser.json" ]
}

@test "launch on Windows without elevation fails precisely BEFORE creating anything" {
  _multicli_is_windows || skip "requires Windows"
  if is_elevated; then skip "host is elevated; the elevation gate cannot fire"; fi
  run env MC_OSUSER_ADAPTER_PATH="$FIXTURE_ADAPTER/adapter.json" \
    bash -c 'source "$OSUSER_LIB"; mc_osuser_launch agy-cli "$1" "C:\fake\agy.exe" --version' _ "$FIXTURE_PROFILE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OS-user isolation for agy-cli/work requires an elevated terminal (Run as Administrator)."* ]]
  run net user "$FIXTURE_USERNAME"
  [ "$status" -ne 0 ]
  [ ! -f "$FIXTURE_PROFILE_DIR/.osuser.json" ]
}

@test "remove with a consistent record on Windows without elevation stops at the elevation gate" {
  _multicli_is_windows || skip "requires Windows"
  if is_elevated; then skip "host is elevated; the elevation gate cannot fire"; fi
  write_ownership "$FIXTURE_USERNAME"
  run osuser_call mc_osuser_remove "$FIXTURE_PROFILE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires an elevated terminal (Run as Administrator)."* ]]
  # The record survives: nothing was deleted.
  [ -f "$FIXTURE_PROFILE_DIR/.osuser.json" ]
}

@test "profile delete preserves an OS-user profile when cleanup fails" {
  _multicli_is_windows || skip "requires Windows"
  if is_elevated; then skip "host is elevated; the elevation gate cannot fire"; fi
  write_ownership "$FIXTURE_USERNAME"

  run bash -c 'printf "y\n" | "$1" delete agy-cli/work' _ "$MULTICLI_BIN"

  [ "$status" -ne 0 ]
  [[ "$output" == *"requires an elevated terminal (Run as Administrator)."* ]]
  [ -d "$FIXTURE_PROFILE_DIR" ]
  [ -f "$FIXTURE_PROFILE_DIR/.osuser.json" ]
}

@test "ensure rejects a missing adapter manifest" {
  _multicli_is_windows || skip "requires Windows"
  run osuser_call mc_osuser_ensure nope "$FIXTURE_PROFILE_DIR" "$MULTICLI_SCRATCH/nope.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown tool 'nope'"* ]]
}
