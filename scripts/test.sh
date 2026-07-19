#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CXX=${CXX:-c++}
BUILD_DIR="$ROOT/build/tests"
mkdir -p "$BUILD_DIR"

"$CXX" -std=c++17 -O2 -Wall -Wextra -Werror \
    -I"$ROOT/Sources/Protocol" \
    "$ROOT/Sources/Protocol/NFCFProfileRecord.cpp" \
    "$ROOT/tests/nfcf_profile_record_test.cpp" \
    -o "$BUILD_DIR/nfcf_profile_record_test"

"$BUILD_DIR/nfcf_profile_record_test"

"$CXX" -std=c++17 -O2 -Wall -Wextra -Werror \
    -I"$ROOT/Sources/Protocol" \
    "$ROOT/Sources/Protocol/FeliCaPollingResponse.cpp" \
    "$ROOT/tests/felica_polling_response_test.cpp" \
    -o "$BUILD_DIR/felica_polling_response_test"

"$BUILD_DIR/felica_polling_response_test"
echo "All portable tests passed."
