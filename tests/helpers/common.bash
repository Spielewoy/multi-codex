# Shared bats helpers for the multi-cli session-continuation suite.
#
# Every test runs the REAL multi-cli launcher against REAL fixture trees built
# in mktemp scratch dirs. No mocks. HOME and MULTICLI_HOME are always redirected
# into scratch so the operator's real ~/.codex / ~/.claude are never touched.

# Absolute path to the repo root (parent of tests/).
MULTICLI_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MULTICLI_BIN="$MULTICLI_REPO_ROOT/multi-cli"
MULTICLI_VENDOR="${MULTICLI_TEST_CACHE:-${TMPDIR:-/tmp}/multi-cli-test-tools}"

# The pinned jq release used when bootstrapping a vendored binary on demand.
MULTICLI_JQ_VERSION="jq-1.7.1"
MULTICLI_JQ_BASE_URL="https://github.com/jqlang/jq/releases/download/$MULTICLI_JQ_VERSION"

# Name of the jq release asset for the current OS/arch, and the local filename
# it should be saved as in the test-tool cache.
_multicli_jq_asset() {
  local os arch
  os="$(uname -s 2>/dev/null || echo unknown)"
  arch="$(uname -m 2>/dev/null || echo unknown)"
  case "$os" in
    Linux)
      case "$arch" in
        x86_64|amd64) echo "jq-linux-amd64 jq" ;;
        aarch64|arm64) echo "jq-linux-arm64 jq" ;;
        *) return 1 ;;
      esac ;;
    Darwin)
      case "$arch" in
        arm64) echo "jq-macos-arm64 jq" ;;
        x86_64) echo "jq-macos-amd64 jq" ;;
        *) return 1 ;;
      esac ;;
    MINGW*|MSYS*|CYGWIN*|Windows*)
      echo "jq-windows-amd64.exe jq.exe" ;;
    *) return 1 ;;
  esac
}

# Download the pinned jq binary into the test-tool cache when neither a system
# jq nor a cached binary exists. Keeps the suite single-command on a fresh machine.
_multicli_bootstrap_jq() {
  local asset local_name url dest
  read -r asset local_name <<<"$(_multicli_jq_asset)" || {
    echo "jq bootstrap: unsupported OS/arch ($(uname -s)/$(uname -m))" >&2
    return 1
  }
  url="$MULTICLI_JQ_BASE_URL/$asset"
  dest="$MULTICLI_VENDOR/$local_name"
  mkdir -p "$MULTICLI_VENDOR"
  echo "Fetching $MULTICLI_JQ_VERSION ($asset) into $dest ..." >&2
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest" || { echo "jq download failed: $url" >&2; return 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url" || { echo "jq download failed: $url" >&2; return 1; }
  else
    echo "jq bootstrap: neither curl nor wget available" >&2
    return 1
  fi
  chmod +x "$dest"
}

# Locate jq: prefer one already on PATH, otherwise the vendored static binary,
# downloading the cached binary on demand. The launcher hard-requires jq;
# git-bash and minimal CI images often lack it, so we prepend the cache.
ensure_jq_on_path() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  if [ -x "$MULTICLI_VENDOR/jq.exe" ] || [ -x "$MULTICLI_VENDOR/jq" ]; then
    PATH="$MULTICLI_VENDOR:$PATH"
    export PATH
    return 0
  fi
  _multicli_bootstrap_jq || {
    echo "jq not found and bootstrap into $MULTICLI_VENDOR failed" >&2
    return 1
  }
  PATH="$MULTICLI_VENDOR:$PATH"
  export PATH
  command -v jq >/dev/null 2>&1
}

# Build an isolated environment for one test. Creates scratch HOME + profile
# root and exports them. The tool's 'base' (e.g. ~/.codex) therefore resolves
# under the scratch HOME, never the operator's real home.
setup_scratch() {
  ensure_jq_on_path
  MULTICLI_SCRATCH="$(mktemp -d "${BATS_TMPDIR:-/tmp}/multicli.XXXXXX")"
  export HOME="$MULTICLI_SCRATCH/home"
  export MULTICLI_HOME="$MULTICLI_SCRATCH/profiles"
  export MULTICLI_TOOLS_DIR="$MULTICLI_SCRATCH/tools"
  mkdir -p "$HOME" "$MULTICLI_HOME" "$MULTICLI_TOOLS_DIR/codex" "$MULTICLI_TOOLS_DIR/cursor"
  cat > "$MULTICLI_TOOLS_DIR/codex/adapter.json" <<'JSON'
{"id":"codex","displayName":"OpenAI Codex CLI","kind":"cli","binary":{"windows":["codex"],"macos":["codex"],"linux":["codex"]},"isolation":{"strategy":"env","env":{"CODEX_HOME":"{profileDir}"}},"share":{"systemHome":"$HOME/.codex","linkable":["config.toml","skills","agents","prompts","mcp-configs","plugins"],"neverLink":["auth.json","sessions","history.jsonl"]},"session":{"portable":true,"paths":["sessions","history.jsonl","archived_sessions","session_index.jsonl"],"credentials":["auth.json"],"resumeHint":"Resume a copied conversation with `codex resume <session-id>`."},"install":"npm i -g @openai/codex","versionCommand":["--version"],"status":"legacy-test"}
JSON
  cat > "$MULTICLI_TOOLS_DIR/cursor/adapter.json" <<'JSON'
{"id":"cursor","displayName":"Cursor","kind":"hybrid","binary":{"windows":["cursor"],"macos":["cursor"],"linux":["cursor"]},"isolation":{"strategy":"userDataDir","args":["--user-data-dir","{profileDir}"]},"share":{"systemHome":"$HOME/.cursor","linkable":[],"neverLink":[]},"session":{"portable":false,"reason":"Chats live in sqlite state databases keyed to the workspace path and cannot be safely merged."},"status":"legacy-test"}
JSON
  CODEX_BASE="$HOME/.codex"
}

teardown_scratch() {
  unset MULTICLI_TOOLS_DIR
  [ -n "${MULTICLI_SCRATCH:-}" ] && rm -rf "$MULTICLI_SCRATCH"
}

# Run the real launcher. Use with bats `run` to capture status/output.
multicli() {
  "$MULTICLI_BIN" "$@"
}

# Compare paths after normalizing separators and, on Windows, drive notation.
assert_same_path() {
  local left="$1" right="$2"
  if _multicli_is_windows; then
    command -v cygpath >/dev/null 2>&1 || return 1
    left="$(cygpath -m "$left")"
    right="$(cygpath -m "$right")"
  else
    left="$(_multicli_canonicalize_path_for_compare "$left")"
    right="$(_multicli_canonicalize_path_for_compare "$right")"
  fi
  [ "${left//\\//}" = "${right//\\//}" ]
}

_multicli_canonicalize_path_for_compare() {
  local path="$1" probe="$1" suffix="" parent
  while [ ! -e "$probe" ] && [ "$probe" != "/" ] && [ "$probe" != "$(dirname "$probe")" ]; do
    suffix="/$(basename "$probe")$suffix"
    parent="$(dirname "$probe")"
    [ "$parent" != "$probe" ] || break
    probe="$parent"
  done
  if [ -e "$probe" ]; then
    if [ -d "$probe" ]; then
      printf '%s%s\n' "$(cd "$probe" && pwd -P)" "$suffix"
    else
      printf '%s/%s%s\n' "$(cd "$(dirname "$probe")" && pwd -P)" "$(basename "$probe")" "$suffix"
    fi
    return 0
  fi
  printf '%s\n' "$path"
}

# --- Fixture builders (real files, real content) ---------------------------

# A genuine Codex rollout file: first line is a real session_meta record,
# followed by message records, mirroring the on-disk format codex writes.
write_rollout() {
  local dir="$1" session_id="$2"
  mkdir -p "$dir"
  local f="$dir/rollout-2026-06-11T10-00-00-$session_id.jsonl"
  {
    printf '%s\n' "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$session_id\",\"timestamp\":\"2026-06-11T10:00:00Z\",\"cwd\":\"/work\",\"originator\":\"codex_cli_rs\"}}"
    printf '%s\n' '{"type":"response_item","payload":{"role":"user","content":[{"type":"input_text","text":"fix the build"}]}}'
    printf '%s\n' '{"type":"response_item","payload":{"role":"assistant","content":[{"type":"output_text","text":"done"}]}}'
  } > "$f"
  printf '%s\n' "$f"
}

write_history() {
  local base_dir="$1"
  mkdir -p "$base_dir"
  printf '%s\n' '{"session":"abc-123","ts":1717495200,"text":"fix the build"}' > "$base_dir/history.jsonl"
}

# A real (fake-secret) auth.json credential file.
write_auth() {
  local base_dir="$1"
  mkdir -p "$base_dir"
  printf '%s\n' '{"OPENAI_API_KEY":"sk-test-DO-NOT-COPY","tokens":{"id_token":"x"}}' > "$base_dir/auth.json"
}

# A nested decoy credential hidden inside sessions/ -- must never be copied.
write_decoy_credential() {
  local sessions_dir="$1"
  mkdir -p "$sessions_dir"
  printf '%s\n' '{"OPENAI_API_KEY":"sk-decoy-MUST-NOT-LEAK"}' > "$sessions_dir/auth.json"
}

write_config() {
  local base_dir="$1"
  mkdir -p "$base_dir"
  printf '%s\n' 'model = "gpt-5"' > "$base_dir/config.toml"
}

# Build a full, realistic codex base (~/.codex) inside the scratch HOME.
seed_codex_base() {
  local sessions_dir="$CODEX_BASE/sessions/2026/06/11"
  write_rollout "$sessions_dir" "abc-123" >/dev/null
  write_history "$CODEX_BASE"
  write_auth "$CODEX_BASE"
  write_decoy_credential "$CODEX_BASE/sessions"
  write_config "$CODEX_BASE"
}

# --- Portable link creation -------------------------------------------------

# Hard-link count of a file, portable across GNU and BSD stat. Mirrors the
# launcher's own file_nlink but lives in the test helper so .bats files can call
# it without sourcing the launcher.
test_file_nlink() {
  stat -c %h "$1" 2>/dev/null || stat -f %l "$1" 2>/dev/null || echo 1
}

# True on git-bash / MSYS / Cygwin (Windows), where POSIX ln has no privilege
# and we must fall back to fsutil / mklink.
_multicli_is_windows() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*|Windows*) return 0 ;;
    *) return 1 ;;
  esac
}

# Create a symlink at $2 pointing at $1. POSIX hosts use `ln -s`; Windows hosts
# fall back to `cmd //c mklink`. Returns nonzero (without aborting) if the host
# refuses; callers should `skip` on failure rather than fail.
make_symlink() {
  local target="$1" link="$2"
  if ! _multicli_is_windows; then
    ln -s "$target" "$link" 2>/dev/null && [ -L "$link" ]
    return
  fi
  local link_win target_win
  link_win="$(cygpath -w "$link" 2>/dev/null || echo "$link")"
  target_win="$(cygpath -w "$target" 2>/dev/null || echo "$target")"
  cmd //c mklink "$link_win" "$target_win" >/dev/null 2>&1
  [ -L "$link" ] || [ -e "$link" ]
}

# Create a hardlink at $2 pointing at the existing file $1. POSIX hosts use
# `ln`; Windows hosts use fsutil, then mklink /H. Returns nonzero (without
# aborting) if the host refuses; callers should `skip` on failure.
make_hardlink() {
  local target="$1" link="$2"
  if ! _multicli_is_windows; then
    ln "$target" "$link" 2>/dev/null && [ -f "$link" ]
    return
  fi
  local link_win target_win
  link_win="$(cygpath -w "$link" 2>/dev/null || echo "$link")"
  target_win="$(cygpath -w "$target" 2>/dev/null || echo "$target")"
  fsutil hardlink create "$link_win" "$target_win" >/dev/null 2>&1 \
    || cmd //c mklink /H "$link_win" "$target_win" >/dev/null 2>&1 || true
  [ -f "$link" ]
}

# Source the launcher so individual functions can be called directly. The
# launcher runs need_jq + dispatch on load; passing 'help' makes that a no-op
# (prints help to the redirected fd and returns without exiting non-zero).
source_launcher() {
  ensure_jq_on_path
  set -- help
  # shellcheck disable=SC1090
  source "$MULTICLI_BIN" >/dev/null 2>&1
}
