#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CLANG=$(xcrun -f clang++)
BUILD_DIR="$ROOT/build/ios-ci"
mkdir -p "$BUILD_DIR"

"$CLANG" -fobjc-arc -fmodules -std=gnu++17 -O2 -Wall -Wextra -Werror \
    -target arm64-apple-ios16.0 -isysroot "$SDK" \
    -F"$SDK/System/Library/Frameworks" \
    -I"$ROOT/Sources/Application" -I"$ROOT/Sources/Models" \
    -I"$ROOT/Sources/Services" -I"$ROOT/Sources/Storage" \
    -I"$ROOT/Sources/UI" -I"$ROOT/Sources/Protocol" \
    "$ROOT/Sources/Application/main.mm" \
    "$ROOT/Sources/Application/AppDelegate.mm" \
    "$ROOT/Sources/Services/BackendClient.mm" \
    "$ROOT/Sources/Services/BackendResult.mm" \
    "$ROOT/Sources/Services/NFCFSessionController.mm" \
    "$ROOT/Sources/Storage/CardStore.mm" \
    "$ROOT/Sources/Storage/CardBackupCodec.mm" \
    "$ROOT/Sources/Storage/StudentCardRepository.mm" \
    "$ROOT/Sources/Models/StudentCard.mm" \
    "$ROOT/Sources/Services/StudentCardReader.mm" \
    "$ROOT/Sources/UI/ViewController.mm" \
    "$ROOT/Sources/Protocol/NFCFProfileRecord.cpp" \
    "$ROOT/Sources/Protocol/FeliCaPollingResponse.cpp" \
    -framework UIKit -framework Foundation -framework CoreGraphics \
    -framework CoreNFC \
    -framework Security -framework UniformTypeIdentifiers -lc++ \
    -o "$BUILD_DIR/IOSDeGakuseisyo"
