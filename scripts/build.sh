#!/bin/bash
# Build IndexPilot for Apple Silicon
# Usage: ./scripts/build.sh [debug|release]

set -eo pipefail

MODE=${1:-debug}
ARCH="arm64"
PLATFORM="macosx"

echo "==> Building IndexPilot ($MODE, $ARCH)"

if [ "$MODE" = "release" ]; then
    swift build \
        -c release \
        --arch "$ARCH" \
        -Xswiftc "-target" \
        -Xswiftc "arm64-apple-macosx14.0"
    echo "==> Build complete: .build/release/IndexPilot"
else
    swift build --arch "$ARCH"
    echo "==> Build complete: .build/debug/IndexPilot"
fi
