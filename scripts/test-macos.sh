#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CXX=${CXX:-$(xcrun -f clang++)}
SDK=${SDK:-$(xcrun --sdk macosx --show-sdk-path)}
BUILD_DIR="$ROOT/build/macos-tests"
mkdir -p "$BUILD_DIR"

"$CXX" -std=gnu++17 -fobjc-arc -Wall -Wextra -Werror \
    -isysroot "$SDK" -F"$SDK/System/Library/Frameworks" \
    -I"$ROOT/Sources/Services" \
    "$ROOT/Sources/Services/BackendResult.mm" \
    "$ROOT/tests/backend_result_test.mm" \
    -framework Foundation -o "$BUILD_DIR/backend_result_test"

"$CXX" -std=gnu++17 -fobjc-arc -Wall -Wextra -Werror \
    -isysroot "$SDK" -F"$SDK/System/Library/Frameworks" \
    -I"$ROOT/Sources/Storage" \
    "$ROOT/Sources/Storage/CardBackupCodec.mm" \
    "$ROOT/tests/card_backup_codec_test.mm" \
    -framework Foundation -o "$BUILD_DIR/card_backup_codec_test"

"$CXX" -std=gnu++17 -fobjc-arc -Wall -Wextra -Werror \
    -isysroot "$SDK" -F"$SDK/System/Library/Frameworks" \
    -I"$ROOT/Sources/Models" -I"$ROOT/Sources/Protocol" \
    "$ROOT/Sources/Models/StudentCard.mm" \
    "$ROOT/Sources/Protocol/NFCFProfileRecord.cpp" \
    "$ROOT/tests/student_card_record_test.mm" \
    -framework Foundation -o "$BUILD_DIR/student_card_record_test"

"$BUILD_DIR/backend_result_test"
"$BUILD_DIR/card_backup_codec_test"
"$BUILD_DIR/student_card_record_test"
echo "All macOS Foundation tests passed."
