#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_SOURCE="$PROJECT_DIR/build/macOS Audio Forward.app"
APP_DESTINATION="/Applications/macOS Audio Forward.app"

if [[ ! -d "$APP_SOURCE" ]]; then
    "$PROJECT_DIR/scripts/build.sh"
fi

osascript -e 'tell application "macOS Audio Forward" to quit' 2>/dev/null || true
for attempt in 1 2 3 4 5; do
    pgrep -x MacOSAudioForward >/dev/null || break
    sleep 1
done
ditto "$APP_SOURCE" "$APP_DESTINATION"
open -n "$APP_DESTINATION"
echo "$APP_DESTINATION"
