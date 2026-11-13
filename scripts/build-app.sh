#!/usr/bin/env bash
set -euo pipefail

# Builds build/MacTubeConverter.app. Whisper models are NOT bundled; the app reads them at
# runtime from MACTUBE_MODEL_DIR, ~/Library/Application Support/MacTubeConverter/Models,
# or the sibling ~/Documents/Mac Apps/Models folder.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MacTubeConverter"
BUNDLE_ID="${MACTUBE_BUNDLE_ID:-com.asjames18.MacTubeConverter}"
VERSION="1.2"
BUILD_NUMBER="3"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="${MACTUBE_ICON:-$ROOT_DIR/Resources/AppIcon.icns}"

BUILD_PATH="${MACTUBE_BUILD_PATH:-$ROOT_DIR/.build}"
cd "$ROOT_DIR"
swift build --scratch-path "$BUILD_PATH" -c release --product "$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_PATH/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"

ICON_PLIST=""
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$RESOURCES_DIR/AppIcon.icns"
  ICON_PLIST="  <key>CFBundleIconFile</key>
  <string>AppIcon</string>"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>MacTube Converter</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.video</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
$ICON_PLIST
</dict>
</plist>
PLIST

# Ad-hoc signature: no Apple Developer account needed; keeps Gatekeeper and TCC happy locally.
codesign --force --sign - --timestamp=none "$APP_DIR"
codesign --verify --strict "$APP_DIR"

echo "$APP_DIR"
