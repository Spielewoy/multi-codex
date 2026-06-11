#!/usr/bin/env bats
# Direct unit tests for adapter_system_home -- the resolver that maps a tool to
# its real system home. Exercised by sourcing the launcher and calling the
# function against scratch adapters, covering branches that the codex adapter
# (which declares share.systemHome) never reaches.

load helpers/common

setup() {
  setup_scratch
}

teardown() {
  teardown_scratch
}

# Helper: source the launcher and point TOOLS_DIR at a scratch adapter dir.
run_system_home() {
  local toolsdir="$1" tool="$2"
  bash -c "
    set -- help
    source '$MULTICLI_BIN' >/dev/null 2>&1
    TOOLS_DIR='$toolsdir'
    HOME='$HOME'
    adapter_system_home '$tool'
  "
}

# Declared share.systemHome wins and $HOME is expanded.
@test "adapter_system_home resolves declared share.systemHome with HOME expansion" {
  local toolsdir="$MULTICLI_SCRATCH/tools"
  mkdir -p "$toolsdir/declared"
  cat > "$toolsdir/declared/adapter.json" <<'JSON'
{ "id":"declared","share":{"systemHome":"$HOME/.declared"} }
JSON
  run run_system_home "$toolsdir" declared
  [ "$status" -eq 0 ]
  [[ "$output" == "$HOME/.declared" ]]
}

# No systemHome: derive the home from the first isolation.env value, stripping
# the {profileDir} placeholder.
@test "adapter_system_home derives home from isolation.env when systemHome absent" {
  local toolsdir="$MULTICLI_SCRATCH/tools"
  mkdir -p "$toolsdir/derived"
  cat > "$toolsdir/derived/adapter.json" <<'JSON'
{ "id":"derived","isolation":{"strategy":"env","env":{"FOO_HOME":"$HOME/.foo/{profileDir}"}} }
JSON
  run run_system_home "$toolsdir" derived
  [ "$status" -eq 0 ]
  [[ "$output" == "$HOME/.foo/" ]]
}

# Neither systemHome nor isolation.env: return non-zero (no home).
@test "adapter_system_home returns non-zero when nothing declares a home" {
  local toolsdir="$MULTICLI_SCRATCH/tools"
  mkdir -p "$toolsdir/nohome"
  cat > "$toolsdir/nohome/adapter.json" <<'JSON'
{ "id":"nohome","isolation":{"strategy":"userDataDir","args":["--x"]} }
JSON
  run run_system_home "$toolsdir" nohome
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}
