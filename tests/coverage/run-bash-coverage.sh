#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="${BASH_COVERAGE_OUTPUT:-${TMPDIR:-/tmp}/multi-cli-coverage/bash}"
MINIMUM_PERCENT="${BASH_COVERAGE_MINIMUM:-95}"
BASELINE="${COVERAGE_BASELINE:-}"
CHANGED_REPORT="${BASH_COVERAGE_CHANGED_REPORT:-$OUTPUT_DIR/changed-lines.json}"
export BASH_COVERAGE_OUTPUT="$OUTPUT_DIR"

if [ -z "$BASELINE" ]; then
  if git -C "$REPO_ROOT" rev-parse --verify --quiet 'HEAD^^{commit}' >/dev/null; then
    BASELINE='HEAD^'
  elif git -C "$REPO_ROOT" rev-parse --verify --quiet 'origin/main^{commit}' >/dev/null; then
    BASELINE='origin/main'
  else
    echo "Cannot resolve a coverage baseline. Set COVERAGE_BASELINE explicitly." >&2
    exit 2
  fi
fi

command -v bashcov >/dev/null 2>&1 || {
  echo "bashcov is required for Bash coverage." >&2
  exit 2
}
command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to enforce the Bash coverage threshold." >&2
  exit 2
}

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
(
  cd "$REPO_ROOT"
  bashcov --root "$REPO_ROOT" -- "$REPO_ROOT/tests/run-bats.sh"
)

SUMMARY="$OUTPUT_DIR/.resultset.json"
[ -f "$SUMMARY" ] || {
  echo "bashcov did not write $SUMMARY." >&2
  exit 1
}
COBERTURA="$OUTPUT_DIR/cobertura.xml"
python3 "$SCRIPT_DIR/simplecov_to_cobertura.py" \
  --input "$SUMMARY" \
  --repo "$REPO_ROOT" \
  --output "$COBERTURA" \
  --pathspec multi-cli \
  --pathspec 'lib/*.sh' \
  --pathspec 'scripts/*.sh' \
  --pathspec 'install/*.sh' \
  --pathspec 'release/*.sh'

python3 "$SCRIPT_DIR/check_changed_coverage.py" \
  --repo "$REPO_ROOT" \
  --baseline "$BASELINE" \
  --coverage-root "$COBERTURA" \
  --minimum "$MINIMUM_PERCENT" \
  --output "$CHANGED_REPORT" \
  --pathspec multi-cli \
  --pathspec 'lib/*.sh' \
  --pathspec 'scripts/*.sh' \
  --pathspec 'install/*.sh' \
  --pathspec 'release/*.sh'

echo "Bash coverage report: $OUTPUT_DIR/index.html"
echo "Changed-line report: $CHANGED_REPORT"
