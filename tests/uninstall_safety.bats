#!/usr/bin/env bats

load helpers/common

setup() {
  setup_scratch
  export PATH="/usr/bin:$PATH"
  export GIT_BASH_BIN="/usr/bin/bash"
  export MULTICLI_BIN_LINK="$MULTICLI_SCRATCH/bin/multi-cli"
  mkdir -p "$(dirname "$MULTICLI_BIN_LINK")"
}

teardown() {
  unset GIT_BASH_BIN MULTICLI_BIN_LINK MULTICLI_INSTALL_DIR MULTICLI_HOME
  teardown_scratch
}

@test "uninstall refuses to remove HOME as the install directory" {
  run env MULTICLI_INSTALL_DIR="$HOME" MULTICLI_HOME="$MULTICLI_SCRATCH/profiles" MULTICLI_BIN_LINK="$MULTICLI_BIN_LINK" \
    bash -c "printf 'y\\nn\\n' | '$MULTICLI_REPO_ROOT/install/uninstall.sh'"

  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to remove unsafe install path"* ]]
}

@test "uninstall refuses to remove a directory that is not a multi-cli install" {
  local foreign_install="$MULTICLI_SCRATCH/foreign-install"
  mkdir -p "$foreign_install"
  printf 'notes\n' > "$foreign_install/readme.txt"

  run env MULTICLI_INSTALL_DIR="$foreign_install" MULTICLI_HOME="$MULTICLI_SCRATCH/profiles" MULTICLI_BIN_LINK="$MULTICLI_BIN_LINK" \
    bash -c "printf 'y\\nn\\n' | '$MULTICLI_REPO_ROOT/install/uninstall.sh'"

  [ "$status" -eq 1 ]
  [[ "$output" == *"not a recognizable multi-cli installation"* ]]
}

@test "uninstall removes a confirmed multi-cli install directory" {
  local install_dir="$MULTICLI_SCRATCH/install"
  mkdir -p "$install_dir/lib"
  printf '#!/usr/bin/env bash\n' > "$install_dir/multi-cli"

  run env MULTICLI_INSTALL_DIR="$install_dir" MULTICLI_HOME="$MULTICLI_SCRATCH/missing-profiles" MULTICLI_BIN_LINK="$MULTICLI_BIN_LINK" \
    bash -c "printf 'y\\n' | '$MULTICLI_REPO_ROOT/install/uninstall.sh'"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed $install_dir"* ]]
  [ ! -e "$install_dir" ]
}
