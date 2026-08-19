#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_CACHE="${MULTICLI_TEST_CACHE:-${TMPDIR:-/tmp}/multi-cli-test-tools}"
SCRATCH="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/multi-cli-osuser.XXXXXX")"
PROFILE_HOME="$SCRATCH/profiles"
OPERATOR_HOME="$SCRATCH/operator"
TOOL="agy-cli"
PROFILE="ci"
PROFILE_DIR="$PROFILE_HOME/$TOOL/$PROFILE"
CREATED_USERNAME=""

cleanup() {
  if [ -n "$CREATED_USERNAME" ]; then
    case "$(uname -s)" in
      Darwin) sudo dscl . -delete "/Users/$CREATED_USERNAME" >/dev/null 2>&1 || true ;;
      Linux) sudo userdel "$CREATED_USERNAME" >/dev/null 2>&1 || true ;;
    esac
  fi
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

mkdir -p "$PROFILE_HOME/bin" "$OPERATOR_HOME"
chmod 711 "$SCRATCH" "$PROFILE_HOME"
export HOME="$OPERATOR_HOME"
export USERPROFILE="$OPERATOR_HOME"
export MULTICLI_HOME="$PROFILE_HOME"
export PATH="$PROFILE_HOME/bin:$TEST_CACHE:$PATH"
export MULTICLI_OVERRIDE_BINARY=/usr/bin/env

"$REPO_ROOT/multi-cli" new "$TOOL/$PROFILE" --no-seed >/dev/null
chmod 711 "$PROFILE_HOME/$TOOL" "$PROFILE_DIR"
PROFILE_ID="$(jq -r '.profileId' "$PROFILE_DIR/.profile.json")"
source "$REPO_ROOT/lib/multicli-osuser.sh"
CREATED_USERNAME="$(mc_osuser_username "$TOOL" "$PROFILE_ID")"

OUTPUT="$($REPO_ROOT/multi-cli launch "$TOOL/$PROFILE")"
printf '%s\n' "$OUTPUT"

printf '%s\n' "$OUTPUT" | grep -Fx "USER=$CREATED_USERNAME" >/dev/null
printf '%s\n' "$OUTPUT" | grep -F "HOME=$PROFILE_DIR/_home" >/dev/null
[ -f "$PROFILE_DIR/.osuser.json" ]
[ "$(jq -r '.username' "$PROFILE_DIR/.osuser.json")" = "$CREATED_USERNAME" ]

printf 'y\n' | "$REPO_ROOT/multi-cli" delete "$TOOL/$PROFILE" >/dev/null
[ ! -e "$PROFILE_DIR" ]
case "$(uname -s)" in
  Darwin) ! dscl . -read "/Users/$CREATED_USERNAME" >/dev/null 2>&1 ;;
  Linux) ! id "$CREATED_USERNAME" >/dev/null 2>&1 ;;
esac
CREATED_USERNAME=""
