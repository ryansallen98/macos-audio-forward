#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
DIST_DIR="$PROJECT_DIR/dist"
ARCHIVE="$DIST_DIR/macOS-Audio-Forward-$VERSION.zip"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    "$PROJECT_DIR/scripts/build.sh"
fi
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
ditto -c -k --sequesterRsrc --keepParent "$PROJECT_DIR/build/macOS Audio Forward.app" "$ARCHIVE"
cd "$DIST_DIR"
shasum -a 256 "${ARCHIVE:t}" > "${ARCHIVE:t}.sha256"

echo "$ARCHIVE"
