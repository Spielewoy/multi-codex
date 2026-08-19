#!/usr/bin/env bash
# uninstall.sh -- Remove multi-cli from macOS/Linux
set -euo pipefail

INSTALL_DIR="${MULTICLI_INSTALL_DIR:-$HOME/.local/share/multi-cli}"
BIN_LINK="${MULTICLI_BIN_LINK:-$HOME/.local/bin/multi-cli}"
PROFILE_DIR="${MULTICLI_HOME:-$HOME/MultiCliProfiles}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_ROOT="$(dirname "$SCRIPT_DIR")"

assert_safe_remove_dir() {
  local target="$1" purpose="$2" resolved parent home_resolved
  [ -d "$target" ] || return 0
  resolved="$(cd "$target" && pwd -P)"
  home_resolved="$(cd "$HOME" 2>/dev/null && pwd -P || printf '%s\n' "$HOME")"
  parent="$(dirname "$resolved")"
  if [ "$resolved" = "/" ] || [ "$resolved" = "$home_resolved" ] || [ "$parent" = "$resolved" ] || [ "$parent" = "/" ]; then
    echo "Error: refusing to remove unsafe $purpose path: $resolved" >&2
    return 1
  fi
}

assert_multi_cli_install() {
  local target="$1"
  [ -f "$target/multi-cli" ] && [ -d "$target/lib" ] || {
    echo "Error: refusing to remove $target because it is not a recognizable multi-cli installation." >&2
    return 1
  }
}

uninstall_adapter_path() {
  local tool="$1" candidate
  for candidate in "$SOURCE_ROOT/ai-tools/$tool/adapter.json" "$INSTALL_DIR/ai-tools/$tool/adapter.json"; do
    [ -f "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

uninstall_profile_resources() {
  local metadata profile_dir tool adapter mechanism profile_id env_var
  local credential_lib="$SOURCE_ROOT/lib/credential-store.sh"
  local osuser_lib="$SOURCE_ROOT/lib/multicli-osuser.sh"
  [ -f "$credential_lib" ] || credential_lib="$INSTALL_DIR/lib/credential-store.sh"
  [ -f "$osuser_lib" ] || osuser_lib="$INSTALL_DIR/lib/multicli-osuser.sh"
  [ -f "$credential_lib" ] && [ -f "$osuser_lib" ] || return 1
  # shellcheck source=lib/credential-store.sh
  source "$credential_lib"
  # shellcheck source=lib/multicli-osuser.sh
  source "$osuser_lib"
  while IFS= read -r -d '' metadata; do
    profile_dir="$(dirname "$metadata")"
    [ -f "$profile_dir/.osuser.json" ] && mc_osuser_remove "$profile_dir"
    tool="$(basename "$(dirname "$profile_dir")")"
    adapter="$(uninstall_adapter_path "$tool" 2>/dev/null || true)"
    [ -n "$adapter" ] || {
      echo "Cannot determine whether '$tool' owns stored credentials because its adapter is missing. Reinstall multi-cli, then retry uninstall." >&2
      return 1
    }
    mechanism="$(jq -r '.account.mechanism // empty' "$adapter")"
    [ "$mechanism" = processSecret ] || continue
    profile_id="$(jq -r '.profileId // empty' "$metadata")"
    env_var="$(jq -r '.account.secret.environmentVariable // empty' "$adapter")"
    [ -n "$profile_id" ] && [ -n "$env_var" ] && \
      mc_cred_clear "$(mc_cred_target "$tool" "$profile_id" "$env_var")"
  done < <(find "$PROFILE_DIR" -type f -name .profile.json -print0 2>/dev/null)
}

echo "multi-cli uninstaller"
echo ""

# install.sh writes a regular launcher file (not a symlink) at BIN_LINK;
# older installs used a symlink. Remove either, but only when the file is
# recognizably ours -- never delete a foreign file that shares the path.
if [ -L "$BIN_LINK" ]; then
  rm -f "$BIN_LINK"
  echo "Removed symlink: $BIN_LINK"
elif [ -f "$BIN_LINK" ] && grep -q 'multi-cli' "$BIN_LINK" 2>/dev/null; then
  rm -f "$BIN_LINK"
  echo "Removed launcher: $BIN_LINK"
fi

remove_install=false
if [ -d "$INSTALL_DIR" ] && [ "$INSTALL_DIR" != "$(pwd)" ]; then
  printf "Remove install directory %s? [y/N] " "$INSTALL_DIR"
  read -r confirm || confirm=""
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    assert_safe_remove_dir "$INSTALL_DIR" "install" || exit 1
    assert_multi_cli_install "$INSTALL_DIR" || exit 1
    remove_install=true
  fi
fi

if [ -d "$PROFILE_DIR" ]; then
  printf "Remove all profiles at %s? [y/N] " "$PROFILE_DIR"
  read -r confirm || confirm=""
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    assert_safe_remove_dir "$PROFILE_DIR" "profile" || exit 1
    uninstall_profile_resources || {
      echo "Error: could not clean all profile-owned credentials or OS users; profiles were preserved." >&2
      exit 1
    }
    rm -rf "$PROFILE_DIR"
    echo "Removed $PROFILE_DIR"
  else
    echo "Profiles kept at $PROFILE_DIR"
  fi
fi

if [ "$remove_install" = true ]; then
  rm -rf "$INSTALL_DIR"
  echo "Removed $INSTALL_DIR"
fi

echo ""
echo "multi-cli uninstalled."
