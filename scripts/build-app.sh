#!/usr/bin/env bash
set -euo pipefail

# Builds a universal (arm64 + x86_64) build/MacTubeConverter.app with yt-dlp, deno, ffmpeg, ffprobe and
# whisper-cli from vendor/bin (scripts/fetch-bundled-tools.sh) inside Contents/Resources/bin.
# Whisper models are NOT bundled; the app offers a one-click download on first run and reads them from MACTUBE_MODEL_DIR, ~/Library/Application Support/MacTubeConverter/Models,
# or the sibling ~/Documents/Mac Apps/Models folder.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MacTubeConverter"
BUNDLE_ID="${MACTUBE_BUNDLE_ID:-com.asjames18.MacTubeConverter}"
VERSION="1.3.1"
BUILD_NUMBER="5"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="${MACTUBE_ICON:-$ROOT_DIR/Resources/AppIcon.icns}"

BUILD_PATH="${MACTUBE_BUILD_PATH:-$ROOT_DIR/.build}"
cd "$ROOT_DIR"
ARCH_FLAGS=()
if [[ "${UNIVERSAL:-1}" == "1" ]]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi
swift build --scratch-path "$BUILD_PATH" -c release --product "$APP_NAME" "${ARCH_FLAGS[@]}"
BIN_PATH="$(swift build --scratch-path "$BUILD_PATH" -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH/$APP_NAME" "$MACOS_DIR/$APP_NAME"

TOOLS_DIR="${MACTUBE_TOOLS_DIR:-$ROOT_DIR/vendor/bin}"
LICENSES_DIR="${MACTUBE_LICENSES_DIR:-$ROOT_DIR/vendor/licenses}"
if [[ -d "$TOOLS_DIR" ]]; then
  mkdir -p "$RESOURCES_DIR/bin" "$RESOURCES_DIR/Licenses"
  for tool in yt-dlp deno ffmpeg ffprobe whisper-cli; do
    [[ -x "$TOOLS_DIR/$tool" ]] || { echo "Missing $TOOLS_DIR/$tool (run scripts/fetch-bundled-tools.sh)" >&2; exit 1; }
    cp "$TOOLS_DIR/$tool" "$RESOURCES_DIR/bin/$tool"
    codesign --force --sign - --timestamp=none "$RESOURCES_DIR/bin/$tool"
  done
  if [[ -d "$LICENSES_DIR" ]]; then cp "$LICENSES_DIR"/* "$RESOURCES_DIR/Licenses/"; fi
  cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/Licenses/"
else
  echo "warning: $TOOLS_DIR not found; building without bundled tools (Homebrew fallback only)" >&2
fi

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
codesign --verify --strict --deep "$APP_DIR"
lipo -info "$MACOS_DIR/$APP_NAME"

echo "$APP_DIR"
