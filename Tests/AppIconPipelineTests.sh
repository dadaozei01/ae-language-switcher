#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
RESOURCE_DIR="$PROJECT_ROOT/Sources/AELanguageSwitcherApp/Resources"
SOURCE_COPY="$RESOURCE_DIR/AppIconSource.png"
EXPECTED_SOURCE_SHA256="4fa6a1980bb5f6e288f20b2da4772dee6e00eb965a57aba00f13a8494a088bc8"
ICON_FILE="$RESOURCE_DIR/AppIcon.icns"
PLIST_FILE="$RESOURCE_DIR/Info.plist"
APP_PATH="$PROJECT_ROOT/outputs/AE中英文切换器.app"
PACKAGED_PLIST="$APP_PATH/Contents/Info.plist"
PACKAGED_ICON="$APP_PATH/Contents/Resources/AppIcon.icns"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ae-language-switcher-icon-test.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

source_hash="$(shasum -a 256 "$SOURCE_COPY" | awk '{ print $1 }')"
test "$source_hash" = "$EXPECTED_SOURCE_SHA256"
source_width="$(sips -g pixelWidth "$SOURCE_COPY" | awk '/pixelWidth:/ { print $2 }')"
source_height="$(sips -g pixelHeight "$SOURCE_COPY" | awk '/pixelHeight:/ { print $2 }')"
test "$source_width" = "1254"
test "$source_height" = "1254"
test "$source_width" = "$source_height"

bash "$PROJECT_ROOT/scripts/make_app_icon.sh"
test -f "$ICON_FILE"

iconutil -c iconset "$ICON_FILE" -o "$TEMP_DIR/AppIcon.iconset"

while read -r filename expected_size; do
    icon_path="$TEMP_DIR/AppIcon.iconset/$filename"
    test -f "$icon_path"
    width="$(sips -g pixelWidth "$icon_path" | awk '/pixelWidth:/ { print $2 }')"
    height="$(sips -g pixelHeight "$icon_path" | awk '/pixelHeight:/ { print $2 }')"
    test "$width" = "$expected_size"
    test "$height" = "$expected_size"
done <<'SIZES'
icon_16x16.png 16
icon_16x16@2x.png 32
icon_32x32.png 32
icon_32x32@2x.png 64
icon_128x128.png 128
icon_128x128@2x.png 256
icon_256x256.png 256
icon_256x256@2x.png 512
icon_512x512.png 512
icon_512x512@2x.png 1024
SIZES

test "$(plutil -extract CFBundleExecutable raw -o - "$PLIST_FILE")" = "AE中英文切换器"
test "$(plutil -extract CFBundleIconFile raw -o - "$PLIST_FILE")" = "AppIcon"
test "$(plutil -extract CFBundlePackageType raw -o - "$PLIST_FILE")" = "APPL"

xcrun swift build -c release \
    --package-path "$PROJECT_ROOT" \
    --scratch-path "$TEMP_DIR/swift-build" 2>&1 | tee "$TEMP_DIR/build.log"
if grep -q "which are unhandled" "$TEMP_DIR/build.log"; then
    echo "SwiftPM reported unhandled application resources." >&2
    exit 1
fi

bash "$PROJECT_ROOT/scripts/package_app.sh"
plutil -lint "$PACKAGED_PLIST"
test "$(plutil -extract CFBundleExecutable raw -o - "$PACKAGED_PLIST")" = "AE中英文切换器"
test "$(plutil -extract CFBundleIconFile raw -o - "$PACKAGED_PLIST")" = "AppIcon"
test "$(plutil -extract CFBundlePackageType raw -o - "$PACKAGED_PLIST")" = "APPL"
test -f "$PACKAGED_ICON"
cmp "$ICON_FILE" "$PACKAGED_ICON"
codesign --verify --deep --strict "$APP_PATH"

echo "App icon pipeline tests passed."
