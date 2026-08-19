#!/usr/bin/env bash
# validate-adapters.sh -- semantically validate every adapter.json under the
# ai-tools directory (or the directory given as $1). Exit 0 when all pass, 1 with one
# error line per violation otherwise. Bash counterpart of
# scripts/Validate-Adapters.ps1.
set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_ROOT="${1:-$REPO_ROOT/ai-tools}"

command -v jq >/dev/null 2>&1 || {
  echo "Error: jq is required to validate adapters." >&2
  exit 1
}

# shellcheck source=../lib/adapter-validation.sh
source "$REPO_ROOT/lib/adapter-validation.sh"

count=0
failed=0
for adapter_dir in "$TOOLS_ROOT"/*/; do
  adapter_dir="${adapter_dir%/}"
  manifest="$adapter_dir/adapter.json"
  [ -f "$manifest" ] || continue
  count=$((count + 1))
  id="$(basename "$adapter_dir")"
  if ! validate_adapter_manifest "$manifest" "$id"; then
    failed=1
    for validation_error in "${ADAPTER_VALIDATION_ERRORS[@]}"; do
      printf '%s: %s\n' "$manifest" "$validation_error" >&2
    done
  fi
done

if [ "$count" -eq 0 ]; then
  echo "No adapters found under $TOOLS_ROOT" >&2
  exit 1
fi

[ "$failed" -eq 0 ] || exit 1
printf 'Validated %d adapter(s).\n' "$count"
