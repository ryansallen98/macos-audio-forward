#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
TEST_BINARY="$(mktemp /tmp/macos-audio-forward-tests.XXXXXX)"
trap 'rm -f "$TEST_BINARY"' EXIT

xcrun swiftc \
    "$PROJECT_DIR/Sources/MacOSAudioForward/AudioProtocol.swift" \
    "$PROJECT_DIR/Tests/AudioProtocolTests.swift" \
    -o "$TEST_BINARY"
"$TEST_BINARY"
