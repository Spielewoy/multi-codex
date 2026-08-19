#!/usr/bin/env bats

load helpers/common

setup() {
  setup_scratch
  export PATH="/usr/bin:$PATH"
  export GIT_BASH_BIN="$(command -v bash)"
  export MULTICLI_BIN_LINK="$MULTICLI_SCRATCH/bin/multi-cli"
  mkdir -p "$(dirname "$MULTICLI_BIN_LINK")"
}

teardown() {
  unset GIT_BASH_BIN MULTICLI_BIN_LINK MULTICLI_INSTALL_DIR MULTICLI_REPO
  teardown_scratch
}

@test "install rejects an unknown option" {
  run "$GIT_BASH_BIN" "$MULTICLI_REPO_ROOT/install/install.sh" --wat

  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option '--wat'"* ]]
}

@test "install rejects placeholder repository URLs" {
  run env MULTICLI_REPO="https://github.com/<owner>/<repo>.git" \
    MULTICLI_BIN_LINK="$MULTICLI_BIN_LINK" \
    "$GIT_BASH_BIN" "$MULTICLI_REPO_ROOT/install/install.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"MULTICLI_REPO contains a placeholder"* ]]
}

@test "install requires git for GitHub installs" {
  local empty_bin="$MULTICLI_SCRATCH/empty-bin"
  mkdir -p "$empty_bin"

  run env PATH="$empty_bin" MULTICLI_REPO="https://github.com/Spielewoy/multi-cli.git" \
    MULTICLI_BIN_LINK="$MULTICLI_BIN_LINK" \
    "$GIT_BASH_BIN" "$MULTICLI_REPO_ROOT/install/install.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"git is required to install multi-cli from GitHub"* ]]
}

@test "install refuses to reuse a non-git directory" {
  export MULTICLI_INSTALL_DIR="$MULTICLI_SCRATCH/existing-install"
  mkdir -p "$MULTICLI_INSTALL_DIR"
  printf 'not a checkout\n' > "$MULTICLI_INSTALL_DIR/README.txt"

  run env MULTICLI_INSTALL_DIR="$MULTICLI_INSTALL_DIR" MULTICLI_BIN_LINK="$MULTICLI_BIN_LINK" \
    MULTICLI_REPO="https://github.com/Spielewoy/multi-cli.git" \
    "$GIT_BASH_BIN" "$MULTICLI_REPO_ROOT/install/install.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"exists but is not a Git checkout"* ]]
}

@test "install rejects a cloned repository that lacks the multi-cli entrypoint" {
  local remote_repo="$MULTICLI_SCRATCH/remote.git"
  local source_repo="$MULTICLI_SCRATCH/source"
  export MULTICLI_INSTALL_DIR="$MULTICLI_SCRATCH/installed"
  git init --bare "$remote_repo" >/dev/null
  git init "$source_repo" >/dev/null
  (
    cd "$source_repo"
    git config user.name "Codex"
    git config user.email "codex@example.invalid"
    printf 'just docs\n' > README.md
    git add README.md
    git commit -m "init" >/dev/null
    git remote add origin "$remote_repo"
    git push origin HEAD:main >/dev/null
  )

  run env MULTICLI_INSTALL_DIR="$MULTICLI_INSTALL_DIR" MULTICLI_BIN_LINK="$MULTICLI_BIN_LINK" \
    MULTICLI_REPO="$remote_repo" \
    "$GIT_BASH_BIN" "$MULTICLI_REPO_ROOT/install/install.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"does not contain the multi-cli entrypoint"* ]]
}

@test "local install writes a launcher that execs the repo entrypoint" {
  run env MULTICLI_BIN_LINK="$MULTICLI_BIN_LINK" \
    "$GIT_BASH_BIN" "$MULTICLI_REPO_ROOT/install/install.sh" --local

  [ "$status" -eq 0 ]
  [ -f "$MULTICLI_BIN_LINK" ]
  grep -Fq "exec $MULTICLI_REPO_ROOT/multi-cli" "$MULTICLI_BIN_LINK"
  [[ "$output" == *"Launcher at $MULTICLI_BIN_LINK"* ]]
}
