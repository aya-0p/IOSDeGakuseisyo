#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
THEOS=${THEOS:-}
SDK=${SDK:-"$(xcrun --sdk iphoneos --show-sdk-path)"}
SDK_VERSION=${SDK_VERSION:-"$(xcrun --sdk iphoneos --show-sdk-version)"}
XCODE_DEVELOPER_DIR=${XCODE_DEVELOPER_DIR:-"$(xcode-select --print-path)"}
LDID=${LDID:-"$(command -v ldid || true)"}
DPKG_DEB=${DPKG_DEB:-"$(command -v dpkg-deb || true)"}
SHA256SUM=${SHA256SUM:-"$(command -v sha256sum || command -v shasum || true)"}

require_command() {
    local command=$1
    if [[ -z "$command" ]]; then
        echo "Required command not found." >&2
        exit 1
    fi
    if [[ "$command" == */* ]]; then
        if [[ ! -x "$command" ]]; then
            echo "Required command not found: $command" >&2
            exit 1
        fi
    elif ! command -v "$command" >/dev/null 2>&1; then
        echo "Required command not found: $command" >&2
        exit 1
    fi
}

require_command "$THEOS"
require_command "$LDID"
require_command "$DPKG_DEB"
require_command "$SHA256SUM"
require_command make
require_command install

if [[ ! -d "$SDK" || ! -d "$XCODE_DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS${SDK_VERSION}.sdk" ]]; then
    echo "iPhoneOS SDK was not found through Xcode." >&2
    exit 1
fi

PACKAGE=$(awk '$1 == "Package:" { print $2 }' "$ROOT/Packaging/control")
VERSION=$(awk '$1 == "Version:" { print $2 }' "$ROOT/Packaging/control")
if [[ -z "$PACKAGE" || -z "$VERSION" ]]; then
    echo "Packaging/control does not contain Package and Version fields." >&2
    exit 1
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ios-de-gakuseisyo.XXXXXX")
trap 'rm -rf -- "$WORK_DIR"' EXIT

cat >"$WORK_DIR/Makefile" <<EOF
THEOS := $THEOS
TARGET := iphone:clang:$SDK_VERSION
ARCHS := arm64
APPLICATION_NAME := IOSDeGakuseisyo

IOSDeGakuseisyo_FILES := \\
	$ROOT/Sources/Application/main.mm \\
	$ROOT/Sources/Application/AppDelegate.mm \\
	$ROOT/Sources/Services/BackendClient.mm \\
	$ROOT/Sources/Services/BackendResult.mm \\
	$ROOT/Sources/Services/NFCFSessionController.mm \\
	$ROOT/Sources/Storage/CardStore.mm \\
	$ROOT/Sources/Storage/CardBackupCodec.mm \\
	$ROOT/Sources/Storage/StudentCardRepository.mm \\
	$ROOT/Sources/Models/StudentCard.mm \\
	$ROOT/Sources/Services/StudentCardReader.mm \\
	$ROOT/Sources/UI/ViewController.mm \\
	$ROOT/Sources/Protocol/NFCFProfileRecord.cpp \\
	$ROOT/Sources/Protocol/FeliCaPollingResponse.cpp
IOSDeGakuseisyo_CFLAGS := -fobjc-arc -fmodules -std=gnu++17
IOSDeGakuseisyo_FRAMEWORKS := UIKit Foundation CoreGraphics CoreNFC Security UniformTypeIdentifiers
IOSDeGakuseisyo_LDFLAGS := -lc++

include \$(THEOS)/makefiles/common.mk
include \$(THEOS_MAKE_PATH)/application.mk
EOF

make -f "$WORK_DIR/Makefile" \
    THEOS="$THEOS" \
    THEOS_PLATFORM_SDK_ROOT="$XCODE_DEVELOPER_DIR" \
    THEOS_OBJ_DIR="$WORK_DIR/obj" \
    THEOS_BUILD_DIR="$WORK_DIR/build"

APP_BINARY=$(find "$WORK_DIR" -type f -path '*/IOSDeGakuseisyo.app/IOSDeGakuseisyo' -print -quit)
if [[ -z "$APP_BINARY" ]]; then
    echo "Theos did not produce the application binary." >&2
    exit 1
fi

STAGE="$WORK_DIR/stage"
APP="$STAGE/var/jb/Applications/IOSDeGakuseisyo.app"
DOCS="$STAGE/var/jb/usr/share/doc/$PACKAGE"
DIST="$ROOT/dist"
OUTPUT="$DIST/${PACKAGE}_${VERSION}_iphoneos-arm64.deb"
mkdir -p "$STAGE/DEBIAN" "$APP" "$DOCS" "$DIST"

install -m 0755 "$APP_BINARY" "$APP/IOSDeGakuseisyo"
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

"$DPKG_DEB" --build --root-owner-group "$STAGE" "$OUTPUT"
if [[ "$SHA256SUM" == */shasum ]]; then
    "$SHA256SUM" -a 256 "$APP/IOSDeGakuseisyo" "$OUTPUT"
else
    "$SHA256SUM" "$APP/IOSDeGakuseisyo" "$OUTPUT"
fi
