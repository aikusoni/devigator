#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
OUTPUT_DIR="$PROJECT_DIR/build"
APP_DIR="$OUTPUT_DIR/Devigator.app"
ASSET_CATALOG="$OUTPUT_DIR/AppIcon.xcassets"
APPICON_SET="$ASSET_CATALOG/AppIcon.appiconset"

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

rm -rf "$ASSET_CATALOG"
mkdir -p "$APPICON_SET"
cp "$PROJECT_DIR/Assets/AppIconContents.json" "$APPICON_SET/Contents.json"
sips -z 16 16 "$PROJECT_DIR/Assets/AppIcon.png" --out "$APPICON_SET/icon_16x16.png" >/dev/null
sips -z 32 32 "$PROJECT_DIR/Assets/AppIcon.png" --out "$APPICON_SET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$PROJECT_DIR/Assets/AppIcon.png" --out "$APPICON_SET/icon_32x32.png" >/dev/null
sips -z 64 64 "$PROJECT_DIR/Assets/AppIcon.png" --out "$APPICON_SET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$PROJECT_DIR/Assets/AppIcon.png" --out "$APPICON_SET/icon_128x128.png" >/dev/null
sips -z 256 256 "$PROJECT_DIR/Assets/AppIcon.png" --out "$APPICON_SET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$PROJECT_DIR/Assets/AppIcon.png" --out "$APPICON_SET/icon_256x256.png" >/dev/null
sips -z 512 512 "$PROJECT_DIR/Assets/AppIcon.png" --out "$APPICON_SET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$PROJECT_DIR/Assets/AppIcon.png" --out "$APPICON_SET/icon_512x512.png" >/dev/null
cp "$PROJECT_DIR/Assets/AppIcon.png" "$APPICON_SET/icon_512x512@2x.png"
xcrun actool "$ASSET_CATALOG" \
    --compile "$APP_DIR/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$OUTPUT_DIR/AppIconInfo.plist" \
    --warnings --notices >/dev/null
chmod +x "$APP_DIR/Contents/MacOS/Devigator"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
