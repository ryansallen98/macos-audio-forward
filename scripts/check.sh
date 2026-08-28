#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
swift build
"$PROJECT_DIR/scripts/test.sh"
"$PROJECT_DIR/scripts/build.sh" >/dev/null
codesign --verify --deep --strict "$PROJECT_DIR/build/macOS Audio Forward.app"
plutil -lint "$PROJECT_DIR/build/macOS Audio Forward.app/Contents/Info.plist"
echo "All checks passed."
