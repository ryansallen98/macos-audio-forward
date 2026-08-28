#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/macOS Audio Forward.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$PROJECT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp ".build/release/MacOSAudioForward" "$CONTENTS_DIR/MacOS/MacOSAudioForward"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "Resources/PrivacyInfo.xcprivacy" "$CONTENTS_DIR/Resources/PrivacyInfo.xcprivacy"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$CONTENTS_DIR/Info.plist"

if [[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
fi

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --options runtime --timestamp=none --sign - \
        --identifier dev.rallen.macos-audio-forward "$APP_DIR"
else
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" \
        --identifier dev.rallen.macos-audio-forward "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
