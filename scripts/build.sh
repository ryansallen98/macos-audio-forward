#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/Audio Forward.app"
CONTENTS_DIR="$APP_DIR/Contents"
ICON_SOURCE="$PROJECT_DIR/Resources/AppIcon.png"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

cd "$PROJECT_DIR"
swift build -c release

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources" "$ICONSET_DIR"
cp ".build/release/MacOSAudioForward" "$CONTENTS_DIR/MacOS/MacOSAudioForward"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "Resources/PrivacyInfo.xcprivacy" "$CONTENTS_DIR/Resources/PrivacyInfo.xcprivacy"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$CONTENTS_DIR/Info.plist"

if [[ -f "$ICON_SOURCE" ]]; then
    sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET_DIR" -o "$CONTENTS_DIR/Resources/AppIcon.icns"
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
