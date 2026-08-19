#!/usr/bin/env bash
# install.sh -- Install multi-cli for macOS/Linux
set -euo pipefail

REPO_URL="${MULTICLI_REPO:-https://github.com/Spielewoy/multi-cli.git}"
INSTALL_DIR="${MULTICLI_INSTALL_DIR:-$HOME/.local/share/multi-cli}"
BIN_LINK="${MULTICLI_BIN_LINK:-$HOME/.local/bin/multi-cli}"

usage() {
  cat <<EOF
multi-cli installer

USAGE
  ./install/install.sh [--local]

OPTIONS
  --local    Install from the current directory instead of cloning from git.

ENVIRONMENT
  MULTICLI_REPO          Git clone URL (default: $REPO_URL)
  MULTICLI_INSTALL_DIR   Install directory (default: $INSTALL_DIR)
  MULTICLI_BIN_LINK      Symlink location (default: $BIN_LINK)

EOF
  exit 0
}

JQ_VERSION="${MULTICLI_JQ_VERSION:-1.7.1}"

# Canonical OS name for asset selection: macos, linux, windows, or unknown.
os_kind() {
  case "$(uname -s)" in
    Darwin)               printf 'macos\n' ;;
    Linux)                printf 'linux\n' ;;
    MINGW*|MSYS*|CYGWIN*) printf 'windows\n' ;;
    *)                    printf 'unknown\n' ;;
  esac
}

# jq release asset name for this OS/arch; returns 1 for unsupported combos.
jq_asset_name() {
  local os="$1" arch
  arch="$(uname -m)"
  case "$os" in
    windows)
      case "$arch" in
        x86_64|amd64) printf 'jq-windows-amd64.exe\n' ;;
        i?86)         printf 'jq-windows-i386.exe\n' ;;
        *)            return 1 ;;
      esac ;;
    macos)
      case "$arch" in
        arm64|aarch64) printf 'jq-macos-arm64\n' ;;
        x86_64|amd64)  printf 'jq-macos-amd64\n' ;;
        *)             return 1 ;;
      esac ;;
    linux)
      case "$arch" in
        x86_64|amd64)  printf 'jq-linux-amd64\n' ;;
        aarch64|arm64) printf 'jq-linux-arm64\n' ;;
        i?86)          printf 'jq-linux-i386\n' ;;
        *)             return 1 ;;
      esac ;;
    *) return 1 ;;
  esac
}

# Download the official static jq binary into the multi-cli bin dir as a
# last-resort fallback when no package manager is available.
install_jq_from_release() {
  local bin_dir="$1" os asset url dest
  os="$(os_kind)"
  asset="$(jq_asset_name "$os")" || return 1
  url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/${asset}"
  command -v curl >/dev/null 2>&1 || return 1

  mkdir -p "$bin_dir"
  if [ "$os" = "windows" ]; then dest="$bin_dir/jq.exe"; else dest="$bin_dir/jq"; fi

  echo "Downloading jq ${JQ_VERSION} from $url"
  curl -fsSL -o "$dest" "$url" || { rm -f "$dest"; return 1; }
  chmod +x "$dest"
  PATH="$bin_dir:$PATH"
  command -v jq >/dev/null 2>&1
}

# Per-platform manual jq install hints, printed when automatic install fails.
jq_manual_instructions() {
  echo "  macOS:        brew install jq" >&2
  echo "  Debian/Ubuntu: sudo apt-get install -y jq" >&2
  echo "  Fedora/RHEL:  sudo dnf install -y jq" >&2
  echo "  Arch:         sudo pacman -S --noconfirm jq" >&2
  echo "  Windows:      winget install jqlang.jq   (or: choco install jq)" >&2
  echo "  Manual:       https://jqlang.github.io/jq/download/" >&2
}

# jq is a hard dependency: the entire CLI is jq-driven. Resolve it now or fail.
ensure_jq() {
  local bin_dir="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "jq found: $(command -v jq)"
    return 0
  fi

  echo "jq is required but not installed. Attempting to install it ..."
  case "$(os_kind)" in
    macos)
      if command -v brew >/dev/null 2>&1; then brew install jq || true; fi
      ;;
    linux)
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y && sudo apt-get install -y jq || true
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y jq || true
      elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y jq || true
      elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm jq || true
      fi
      ;;
    windows)
      if command -v winget >/dev/null 2>&1; then
        winget install --id jqlang.jq -e --source winget \
          --accept-package-agreements --accept-source-agreements || true
      elif command -v choco >/dev/null 2>&1; then
        choco install jq -y || true
      fi
      ;;
  esac

  if command -v jq >/dev/null 2>&1; then
    echo "Installed jq: $(command -v jq)"
    return 0
  fi

  # No package manager succeeded, so fall back to the official static binary.
  if install_jq_from_release "$bin_dir"; then
    echo "Installed jq to $bin_dir: $(command -v jq)"
    return 0
  fi

  echo "" >&2
  echo "Error: jq is required but could not be installed automatically." >&2
  echo "multi-cli is entirely jq-driven and will not run without it." >&2
  echo "Install jq manually, then re-run this installer:" >&2
  jq_manual_instructions
  exit 1
}

local_install=false
for arg in "$@"; do
  case "$arg" in
    --local) local_install=true ;;
    --help|-h) usage ;;
    *) echo "Error: unknown option '$arg'. Run with --help for usage." >&2; exit 2 ;;
  esac
done

echo "multi-cli installer"
echo ""

if [ "$local_install" = true ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  INSTALL_DIR="$(dirname "$SCRIPT_DIR")"
  echo "Installing from local directory: $INSTALL_DIR"
else
  if [[ "$REPO_URL" == *"<owner>"* ]] || [[ "$REPO_URL" == *"<repo>"* ]]; then
    echo "Error: MULTICLI_REPO contains a placeholder. Set it to the actual git clone URL." >&2
    echo "  export MULTICLI_REPO=https://github.com/Spielewoy/multi-cli.git" >&2
    exit 1
  fi
  command -v git >/dev/null 2>&1 || {
    echo "Error: git is required to install multi-cli from GitHub." >&2
    exit 1
  }
  echo "Cloning from $REPO_URL ..."
  if [ -d "$INSTALL_DIR" ]; then
    [ -e "$INSTALL_DIR/.git" ] || {
      echo "Error: $INSTALL_DIR exists but is not a Git checkout." >&2
      echo "Move it, choose MULTICLI_INSTALL_DIR, or use --local from a multi-cli checkout." >&2
      exit 1
    }
    echo "Updating existing installation at $INSTALL_DIR"
    git -C "$INSTALL_DIR" pull --ff-only
  else
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
fi

[ -f "$INSTALL_DIR/multi-cli" ] || {
  echo "Error: $INSTALL_DIR does not contain the multi-cli entrypoint." >&2
  exit 1
}
chmod +x "$INSTALL_DIR/multi-cli"

ensure_jq "$(dirname "$BIN_LINK")"

# A launcher that execs the real script in the repo. A bare symlink breaks
# adapter discovery: multi-cli derives its tools dir from $0, and a symlink's
# dirname is the link location (and on MSYS `ln -sf` copies, losing the repo
# entirely). Exec'ing the absolute path keeps $0 pointed at the repo.
mkdir -p "$(dirname "$BIN_LINK")"
printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$INSTALL_DIR/multi-cli" > "$BIN_LINK"
chmod +x "$BIN_LINK"

echo ""
echo "Installed multi-cli to $INSTALL_DIR"
echo "Launcher at $BIN_LINK"

if ! command -v multi-cli >/dev/null 2>&1; then
  echo ""
  echo "NOTE: $(dirname "$BIN_LINK") is not in your PATH."
  echo "Add this to your shell profile (~/.bashrc, ~/.zshrc):"
  echo ""
  echo "  export PATH=\"$(dirname "$BIN_LINK"):\$PATH\""
fi

echo ""
echo "Run 'multi-cli doctor' to verify your setup."
