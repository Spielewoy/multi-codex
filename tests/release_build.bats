#!/usr/bin/env bats

load helpers/common

setup() {
  setup_scratch
  export PATH="/usr/bin:$PATH"
  export GIT_BASH_BIN="/usr/bin/bash"
  export RELEASE_SCRIPT="$MULTICLI_REPO_ROOT/scripts/release-build.sh"
}

teardown() {
  unset GIT_BASH_BIN RELEASE_SCRIPT
  teardown_scratch
}

@test "release build check mode validates synchronized version metadata" {
  run "$GIT_BASH_BIN" "$RELEASE_SCRIPT" --check --version 1.0.0

  [ "$status" -eq 0 ]
  [ "$output" = "Version metadata is synchronized at 1.0.0." ]
}

@test "release build rejects version mismatches" {
  run "$GIT_BASH_BIN" "$RELEASE_SCRIPT" --check --version 9.9.9

  [ "$status" -eq 1 ]
  [[ "$output" == *"Expected version 9.9.9, found 1.0.0"* ]]
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
  [[ "$output" == *"multi-cli-v1.0.0/scripts/install.sh"* ]]
}
