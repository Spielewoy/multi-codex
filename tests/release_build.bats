#!/usr/bin/env bats

load helpers/common

setup() {
  setup_scratch
  export PATH="/usr/bin:$PATH"
  export GIT_BASH_BIN="$(command -v bash)"
  export RELEASE_SCRIPT="$MULTICLI_REPO_ROOT/release/build.sh"
  export RELEASE_BACKUP_DIR="$MULTICLI_SCRATCH/release-originals"
  mkdir -p "$RELEASE_BACKUP_DIR"
  cp "$MULTICLI_REPO_ROOT/release/VERSION" "$RELEASE_BACKUP_DIR/VERSION"
  cp "$MULTICLI_REPO_ROOT/multi-cli" "$RELEASE_BACKUP_DIR/multi-cli"
  cp "$MULTICLI_REPO_ROOT/multi-cli.ps1" "$RELEASE_BACKUP_DIR/multi-cli.ps1"
}

teardown() {
  if [ -d "${RELEASE_BACKUP_DIR:-}" ]; then
    cp "$RELEASE_BACKUP_DIR/VERSION" "$MULTICLI_REPO_ROOT/release/VERSION"
    cp "$RELEASE_BACKUP_DIR/multi-cli" "$MULTICLI_REPO_ROOT/multi-cli"
    cp "$RELEASE_BACKUP_DIR/multi-cli.ps1" "$MULTICLI_REPO_ROOT/multi-cli.ps1"
  fi
  unset GIT_BASH_BIN RELEASE_SCRIPT RELEASE_BACKUP_DIR
  teardown_scratch
}

@test "release build check mode validates synchronized version metadata" {
  run "$GIT_BASH_BIN" "$RELEASE_SCRIPT" --check --version 1.0.0

  [ "$status" -eq 0 ]
  [ "$output" = "Version metadata is synchronized at 1.0.0." ]
}

@test "release build prints usage for --help" {
  run "$GIT_BASH_BIN" "$RELEASE_SCRIPT" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Build the portable Multi-CLI archive."* ]]
  [[ "$output" == *"Usage: release/build.sh"* ]]
}

@test "release build rejects unknown options and prints usage" {
  run "$GIT_BASH_BIN" "$RELEASE_SCRIPT" --wat

  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown option: --wat"* ]]
  [[ "$output" == *"Usage: release/build.sh"* ]]
}

@test "release build rejects version mismatches" {
  run "$GIT_BASH_BIN" "$RELEASE_SCRIPT" --check --version 9.9.9

  [ "$status" -eq 1 ]
  [[ "$output" == *"Expected version 9.9.9, found 1.0.0"* ]]
}

@test "release build rejects an invalid release version file" {
  printf '1.0\n' > "$MULTICLI_REPO_ROOT/release/VERSION"

  run "$GIT_BASH_BIN" "$RELEASE_SCRIPT" --check
  cp "$RELEASE_BACKUP_DIR/VERSION" "$MULTICLI_REPO_ROOT/release/VERSION"

  [ "$status" -eq 1 ]
  [[ "$output" == *"release/VERSION must contain X.Y.Z"* ]]
}

@test "release build rejects a mismatched Bash launcher version" {
  printf 'VERSION=\"9.9.9\"\n' > "$MULTICLI_REPO_ROOT/multi-cli"

  run "$GIT_BASH_BIN" "$RELEASE_SCRIPT" --check
  cp "$RELEASE_BACKUP_DIR/multi-cli" "$MULTICLI_REPO_ROOT/multi-cli"

  [ "$status" -eq 1 ]
  [[ "$output" == *"multi-cli does not embed version 1.0.0"* ]]
}

@test "release build rejects a mismatched PowerShell launcher version" {
  printf "\$VERSION = '9.9.9'\n" > "$MULTICLI_REPO_ROOT/multi-cli.ps1"

  run "$GIT_BASH_BIN" "$RELEASE_SCRIPT" --check
  cp "$RELEASE_BACKUP_DIR/multi-cli.ps1" "$MULTICLI_REPO_ROOT/multi-cli.ps1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"multi-cli.ps1 does not embed version 1.0.0"* ]]
}

@test "release build rejects unsafe output directories" {
  run "$GIT_BASH_BIN" "$RELEASE_SCRIPT" --output /

  [ "$status" -eq 1 ]
  [[ "$output" == *"Refusing unsafe output directory: /"* ]]
}

@test "release build creates the portable archive with the documented assets" {
  local out_dir="$MULTICLI_SCRATCH/release"
  local archive="$out_dir/multi-cli-v1.0.0-linux-macos.tar.gz"

  run "$GIT_BASH_BIN" "$RELEASE_SCRIPT" --output "$out_dir" --version 1.0.0

  [ "$status" -eq 0 ]
  [ -f "$archive" ]
  run tar -tzf "$archive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"multi-cli-v1.0.0/README.md"* ]]
  [[ "$output" == *"multi-cli-v1.0.0/assets/banner.svg"* ]]
  [[ "$output" == *"multi-cli-v1.0.0/ai-tools/codex/adapter.json"* ]]
  [[ "$output" != *"multi-cli-v1.0.0/codex/adapter.json"* ]]
  [[ "$output" == *"multi-cli-v1.0.0/install/install.sh"* ]]
}
