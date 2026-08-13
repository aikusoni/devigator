#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
INFO_PLIST="$PROJECT_DIR/Packaging/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
ARCH=$(uname -m)
DIST_DIR="$PROJECT_DIR/dist"
APP_PATH="$PROJECT_DIR/build/Devigator.app"
DMG_PATH="$DIST_DIR/Devigator-$VERSION.dmg"
ZIP_PATH="$DIST_DIR/Devigator-$VERSION-macos-$ARCH.zip"
CHECKSUM_PATH="$DIST_DIR/SHA256SUMS.txt"
STAGING_ROOT=$(mktemp -d /tmp/devigator-package.XXXXXX)
DMG_ROOT="$STAGING_ROOT/Devigator"

cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

cd "$PROJECT_DIR"
"$PROJECT_DIR/scripts/build-app.sh"

mkdir -p "$DIST_DIR" "$DMG_ROOT"
rm -f "$DMG_PATH" "$ZIP_PATH" "$CHECKSUM_PATH"

ditto "$APP_PATH" "$DMG_ROOT/Devigator.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
    -volname "Devigator $VERSION" \
    -srcfolder "$DMG_ROOT" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$DMG_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

cd "$DIST_DIR"
shasum -a 256 "${DMG_PATH:t}" "${ZIP_PATH:t}" > "$CHECKSUM_PATH"

codesign --verify --deep --strict "$APP_PATH"
hdiutil verify "$DMG_PATH"

echo "$DMG_PATH"
echo "$ZIP_PATH"
echo "$CHECKSUM_PATH"
