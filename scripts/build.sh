#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
THEOS=${THEOS:-"$HOME/theos"}
TOOLCHAIN=${TOOLCHAIN:-"$THEOS/toolchain/linux/iphone/bin"}
SDK=${SDK:-"$THEOS/sdks/iPhoneOS16.5.sdk"}

if [[ ! -d "$SDK" ]]; then
    echo "Set SDK to a legally obtained iPhoneOS SDK directory." >&2
    exit 1
fi

CLANG=${CLANG:-"$TOOLCHAIN/clang"}
LDID=${LDID:-"$TOOLCHAIN/ldid"}
for command in "$CLANG" "$LDID" dpkg-deb install sha256sum; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Required command not found: $command" >&2
        exit 1
    fi
done

PACKAGE=$(awk '$1 == "Package:" { print $2 }' "$ROOT/Packaging/control")
VERSION=$(awk '$1 == "Version:" { print $2 }' "$ROOT/Packaging/control")
if [[ -z "$PACKAGE" || -z "$VERSION" ]]; then
    echo "Packaging/control does not contain Package and Version fields." >&2
    exit 1
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ios-de-gakuseisyo.XXXXXX")
trap 'rm -rf -- "$WORK_DIR"' EXIT

STAGE="$WORK_DIR/stage"
APP="$STAGE/var/jb/Applications/IOSDeGakuseisyo.app"
DOCS="$STAGE/var/jb/usr/share/doc/$PACKAGE"
DIST="$ROOT/dist"
OUTPUT="$DIST/${PACKAGE}_${VERSION}_iphoneos-arm64.deb"
mkdir -p "$STAGE/DEBIAN" "$APP" "$DOCS" "$DIST"

"$CLANG" -fobjc-arc -fmodules -O2 -Wall -Wextra -Werror \
    -std=gnu++17 \
    -target arm64-apple-ios16.0 -isysroot "$SDK" \
    -F"$SDK/System/Library/Frameworks" \
    -I"$ROOT/Sources/Application" \
    -I"$ROOT/Sources/Models" \
    -I"$ROOT/Sources/Services" \
    -I"$ROOT/Sources/Storage" \
    -I"$ROOT/Sources/UI" \
    -I"$ROOT/Sources/Protocol" \
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
    -Wl,-no_auth_data \
    -o "$APP/IOSDeGakuseisyo"

"$LDID" -S"$ROOT/Packaging/entitlements.plist" "$APP/IOSDeGakuseisyo"
install -m 0644 "$ROOT/Resources/Info.plist" "$APP/Info.plist"
for icon in \
    Icon-20@2x.png Icon-20@3x.png \
    Icon-29@2x.png Icon-29@3x.png \
    Icon-40@2x.png Icon-40@3x.png \
    Icon-60@2x.png Icon-60@3x.png \
    Icon-1024.png PackageIcon.png; do
    install -m 0644 "$ROOT/Resources/$icon" "$APP/$icon"
done

install -m 0644 "$ROOT/Packaging/control" "$STAGE/DEBIAN/control"
install -m 0755 "$ROOT/Packaging/postinst" "$STAGE/DEBIAN/postinst"
install -m 0755 "$ROOT/Packaging/prerm" "$STAGE/DEBIAN/prerm"
install -m 0755 "$ROOT/Packaging/postrm" "$STAGE/DEBIAN/postrm"
install -m 0644 "$ROOT/LICENSE" "$DOCS/LICENSE"

dpkg-deb --build --root-owner-group "$STAGE" "$OUTPUT"
sha256sum "$APP/IOSDeGakuseisyo" "$OUTPUT"
