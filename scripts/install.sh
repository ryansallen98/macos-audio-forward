#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_SOURCE="$PROJECT_DIR/build/Audio Forward.app"
APP_DESTINATION="/Applications/Audio Forward.app"
LEGACY_APP="/Applications/macOS Audio Forward.app"

if [[ ! -d "$APP_SOURCE" ]]; then
    "$PROJECT_DIR/scripts/build.sh"
fi

osascript -e 'tell application "Audio Forward" to quit' 2>/dev/null || true
osascript -e 'tell application "macOS Audio Forward" to quit' 2>/dev/null || true
pkill -TERM -x MacOSAudioForward 2>/dev/null || true
for attempt in 1 2 3 4 5; do
    pgrep -x MacOSAudioForward >/dev/null || break
    sleep 1
done

if [[ -d "$LEGACY_APP" ]]; then
    mv "$LEGACY_APP" "$HOME/.Trash/macOS Audio Forward-previous-$(date +%Y%m%d-%H%M%S).app"
fi

ditto "$APP_SOURCE" "$APP_DESTINATION"
open "$APP_DESTINATION"
echo "$APP_DESTINATION"
