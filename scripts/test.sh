#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
TEST_BINARY="$(mktemp /tmp/macos-audio-forward-tests.XXXXXX)"
BUFFER_TEST_BINARY="$(mktemp /tmp/macos-audio-forward-buffer-tests.XXXXXX)"
trap 'rm -f "$TEST_BINARY" "$BUFFER_TEST_BINARY"' EXIT

xcrun swiftc \
    "$PROJECT_DIR/Sources/MacOSAudioForward/AudioProtocol.swift" \
    "$PROJECT_DIR/Tests/AudioProtocolTests.swift" \
    -o "$TEST_BINARY"
"$TEST_BINARY"

xcrun clang \
    -std=c11 \
    -I "$PROJECT_DIR/Sources/AudioForwardBuffer/include" \
    "$PROJECT_DIR/Sources/AudioForwardBuffer/AudioForwardBuffer.c" \
    "$PROJECT_DIR/Tests/AudioRingBufferTests.c" \
    -o "$BUFFER_TEST_BINARY"
"$BUFFER_TEST_BINARY"
