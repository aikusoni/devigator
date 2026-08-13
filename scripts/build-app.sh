#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
OUTPUT_DIR="$PROJECT_DIR/build"
APP_DIR="$OUTPUT_DIR/Devigator.app"

cd "$PROJECT_DIR"
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Devigator" "$APP_DIR/Contents/MacOS/Devigator"
cp "$PROJECT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Sources/Devigator/Resources/DefaultProfiles.json" \
   "$APP_DIR/Contents/Resources/DefaultProfiles.json"
cp "$PROJECT_DIR/Sources/Devigator/Resources/CapabilityCatalog.json" \
   "$APP_DIR/Contents/Resources/CapabilityCatalog.json"
chmod +x "$APP_DIR/Contents/MacOS/Devigator"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
