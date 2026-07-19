#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BACKEND=${IOS_NFCF_BACKEND_SOURCE:-"$ROOT/../iOSNFCFCardEmulation"}
if [[ ! -d "$BACKEND/Sources/Core" ]]; then
    echo "Sibling iOSNFCFCardEmulation checkout not found; golden tests remain authoritative."
    exit 0
fi

compare() {
    local application_file=$1
    local backend_file=$2
    if ! cmp -s "$application_file" "$backend_file"; then
        echo "Shared protocol file differs: $application_file" >&2
        return 1
    fi
}

compare "$ROOT/Sources/Protocol/NFCFProfileRecord.hpp" \
        "$BACKEND/Sources/Core/NFCFProfileRecord.hpp"
compare "$ROOT/Sources/Protocol/NFCFProfileRecord.cpp" \
        "$BACKEND/Sources/Core/NFCFProfileRecord.cpp"
echo "Shared NFC-F profile record is synchronized."
