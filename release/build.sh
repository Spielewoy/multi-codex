#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${TMPDIR:-/tmp}/multi-cli-release"
EXPECTED_VERSION=""
CHECK_ONLY=false

usage() {
  cat <<'EOF'
Build the portable Multi-CLI archive.

Usage: release/build.sh [--check] [--output DIR] [--version X.Y.Z]

  --check          Verify version metadata without building an archive.
  --output DIR     Write the archive to DIR.
  --version X.Y.Z  Require this exact release version.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=true ;;
    --output)
      [ "$#" -ge 2 ] || { echo "--output requires a directory" >&2; exit 2; }
      OUTPUT_DIR="$2"
      shift
      ;;
    --version)
      [ "$#" -ge 2 ] || { echo "--version requires X.Y.Z" >&2; exit 2; }
      EXPECTED_VERSION="$2"
      shift
      ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/release/VERSION")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "release/VERSION must contain X.Y.Z" >&2
  exit 1
}

[ -z "$EXPECTED_VERSION" ] || [ "$VERSION" = "$EXPECTED_VERSION" ] || {
  echo "Expected version $EXPECTED_VERSION, found $VERSION" >&2
  exit 1
}

tr -d '\r' < "$ROOT_DIR/multi-cli" | grep -Fx "VERSION=\"$VERSION\"" > /dev/null || {
  echo "multi-cli does not embed version $VERSION" >&2
  exit 1
}
tr -d '\r' < "$ROOT_DIR/multi-cli.ps1" | grep -Fx "\$VERSION = '$VERSION'" > /dev/null || {
  echo "multi-cli.ps1 does not embed version $VERSION" >&2
  exit 1
}

echo "Version metadata is synchronized at $VERSION."
[ "$CHECK_ONLY" = false ] || exit 0

ARCHIVE_ROOT="multi-cli-v$VERSION"

case "$OUTPUT_DIR" in
  ""|/|"$HOME"|/[A-Za-z]|[A-Za-z]:|[A-Za-z]:/|[A-Za-z]:\\)
    echo "Refusing unsafe output directory: $OUTPUT_DIR" >&2
    exit 1
    ;;
esac

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
STAGE_DIR="$OUTPUT_DIR/$ARCHIVE_ROOT"
ARCHIVE_PATH="$OUTPUT_DIR/$ARCHIVE_ROOT-linux-macos.tar.gz"
rm -rf "$STAGE_DIR"
rm -f "$ARCHIVE_PATH"
mkdir -p "$STAGE_DIR"

copy_path() {
  local relative="$1" source="$ROOT_DIR/$1" destination="$STAGE_DIR/$1"
  [ -e "$source" ] || { echo "Missing release path: $relative" >&2; exit 1; }
  mkdir -p "$(dirname "$destination")"
  cp -R "$source" "$destination"
}

paths=(
  LICENSE README.md assets/banner.svg assets/i18n docs lib schema ai-tools
  multi-cli install/install.sh install/uninstall.sh scripts/icon.icns
)

for path in "${paths[@]}"; do
  copy_path "$path"
done

chmod +x "$STAGE_DIR/multi-cli" "$STAGE_DIR/install/install.sh" "$STAGE_DIR/install/uninstall.sh"
COPYFILE_DISABLE=1 tar -C "$OUTPUT_DIR" -czf "$ARCHIVE_PATH" "$ARCHIVE_ROOT"
rm -rf "$STAGE_DIR"

echo "Created $ARCHIVE_PATH"
