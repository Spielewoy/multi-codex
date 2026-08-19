#!/usr/bin/env bats
# Real-execution tests for install/uninstall.sh. install.sh writes a regular
# launcher FILE (not a symlink) at MULTICLI_BIN_LINK; uninstall must remove
# that file as well as legacy symlinks, and leave foreign files alone.

load helpers/common

setup() {
  setup_scratch
  export MULTICLI_INSTALL_DIR="$MULTICLI_SCRATCH/install"
  export MULTICLI_BIN_LINK="$MULTICLI_SCRATCH/bin/multi-cli"
  export MULTICLI_HOME="$MULTICLI_SCRATCH/profiles-removed"
  mkdir -p "$(dirname "$MULTICLI_BIN_LINK")"
  MULTICLI_TEST_TARGETS=()
}

teardown() {
  local target
  for target in ${MULTICLI_TEST_TARGETS[@]+"${MULTICLI_TEST_TARGETS[@]}"}; do
    bash -c 'source "$1"; mc_cred_clear "$2" >/dev/null 2>&1 || true' _ \
      "$MULTICLI_REPO_ROOT/lib/credential-store.sh" "$target"
  done
  unset MULTICLI_INSTALL_DIR MULTICLI_BIN_LINK
  teardown_scratch
}

# Run the uninstaller, declining the install-dir and profile-dir prompts.
run_uninstall() {
  printf 'n\nn\n' | bash "$MULTICLI_REPO_ROOT/install/uninstall.sh"
}

@test "uninstall removes the regular-file launcher written by install.sh" {
  printf '#!/usr/bin/env bash\nexec "%s/multi-cli" "$@"\n' "$MULTICLI_INSTALL_DIR" > "$MULTICLI_BIN_LINK"
  chmod +x "$MULTICLI_BIN_LINK"

  run run_uninstall

  [ "$status" -eq 0 ]
  [ ! -e "$MULTICLI_BIN_LINK" ]
}

@test "uninstall removes a symlink launcher" {
  local target="$MULTICLI_SCRATCH/install/multi-cli"
  mkdir -p "$MULTICLI_SCRATCH/install"
  printf '#!/usr/bin/env bash\nexec "/opt/multi-cli/multi-cli" "$@"\n' > "$target"
  ln -s "$target" "$MULTICLI_BIN_LINK" 2>/dev/null
  [ -L "$MULTICLI_BIN_LINK" ] || skip "host has no real symlinks (MSYS ln -s copies)"

  run run_uninstall

  [ "$status" -eq 0 ]
  [ ! -e "$MULTICLI_BIN_LINK" ]
}

@test "uninstall leaves an unrelated file at the launcher path alone" {
  printf 'echo unrelated\n' > "$MULTICLI_BIN_LINK"

  run run_uninstall

  [ "$status" -eq 0 ]
  [ -f "$MULTICLI_BIN_LINK" ]
}

@test "uninstall clears process-secret credentials before removing profiles" {
  local tools="$MULTICLI_SCRATCH/tools"
  mkdir -p "$tools/secretcli" "$MULTICLI_HOME/secretcli/account-a"
  cat > "$tools/secretcli/adapter.json" <<'JSON'
{"schemaVersion":2,"id":"secretcli","account":{"mechanism":"processSecret","secret":{"environmentVariable":"SECRETCLI_TOKEN"}}}
JSON
  local profile_id="11111111-2222-3333-4444-555555555555"
  printf '{"schemaVersion":2,"adapterId":"secretcli","profileId":"%s","mode":"accountOverlay"}\n' "$profile_id" \
    > "$MULTICLI_HOME/secretcli/account-a/.profile.json"
  local target="multi-cli/secretcli/$profile_id/SECRETCLI_TOKEN"
  run bash -c 'source "$1"; mc_cred_set "$2" token' _ "$MULTICLI_REPO_ROOT/lib/credential-store.sh" "$target"
  [ "$status" -eq 0 ]
  MULTICLI_TEST_TARGETS+=("$target")
  mkdir -p "$MULTICLI_INSTALL_DIR/ai-tools"
  cp -R "$tools/secretcli" "$MULTICLI_INSTALL_DIR/ai-tools/"

  run bash -c "printf 'n\\ny\\n' | '$MULTICLI_REPO_ROOT/install/uninstall.sh'"

  [ "$status" -eq 0 ]
  [ ! -e "$MULTICLI_HOME" ]
  run bash -c 'source "$1"; mc_cred_present "$2"' _ "$MULTICLI_REPO_ROOT/lib/credential-store.sh" "$target"
  [ "$status" -ne 0 ]
  MULTICLI_TEST_TARGETS=()
}
