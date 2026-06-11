#!/usr/bin/env bash
# Single documented entrypoint for the multi-cli bash test suite.
#
#   tests/run-bats.sh            # run every *.bats file
#   tests/run-bats.sh foo.bats   # run a specific file
#
# Self-contained: works on a fresh machine with neither bats nor jq on PATH.
#   - bats: uses a preinstalled `bats` if present; otherwise uses the vendored
#     bats-core (tests/vendor/bats-core, pinned v1.11.0), cloning it on demand.
#   - jq:   uses a jq already on PATH; otherwise the vendored static binary
#     (tests/vendor/jq[.exe]), downloading it on demand.
# The vendored copies live under tests/vendor/ (git-ignored). Whatever is
# already on disk is reused as-is; nothing is re-fetched when present.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
VENDOR_DIR="$TESTS_DIR/vendor"
BATS_VERSION="v1.11.0"
BATS_REPO="https://github.com/bats-core/bats-core"
BATS_DIR="$VENDOR_DIR/bats-core"
VENDORED_BATS_BIN="$BATS_DIR/bin/bats"

# Source the shared jq bootstrap so local dev and CI resolve jq identically.
# shellcheck source=tests/helpers/common.bash
source "$TESTS_DIR/helpers/common.bash"

# Clone the pinned bats-core into tests/vendor when neither a preinstalled bats
# nor the vendored copy is available.
bootstrap_vendored_bats() {
  [ -x "$VENDORED_BATS_BIN" ] && return 0
  command -v git >/dev/null 2>&1 || {
    echo "git not found; cannot bootstrap bats-core into $BATS_DIR" >&2
    return 1
  }
  echo "Fetching bats-core $BATS_VERSION into $BATS_DIR ..." >&2
  rm -rf "$BATS_DIR"
  mkdir -p "$VENDOR_DIR"
  git clone --depth 1 --branch "$BATS_VERSION" "$BATS_REPO" "$BATS_DIR" >&2
  [ -x "$VENDORED_BATS_BIN" ] || {
    echo "bats clone succeeded but $VENDORED_BATS_BIN is missing or not executable" >&2
    return 1
  }
}

resolve_bats_bin() {
  if command -v bats >/dev/null 2>&1; then
    command -v bats
    return 0
  fi
  bootstrap_vendored_bats || return 1
  printf '%s\n' "$VENDORED_BATS_BIN"
}

BATS_BIN="$(resolve_bats_bin)" || { echo "no bats available and bootstrap failed" >&2; exit 1; }

# Make jq discoverable to the launcher for the whole run (download if needed).
ensure_jq_on_path || { echo "jq not available and bootstrap failed" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not on PATH after bootstrap" >&2; exit 1; }

if [ "$#" -gt 0 ]; then
  exec "$BATS_BIN" "$@"
fi

exec "$BATS_BIN" "$TESTS_DIR"/*.bats
