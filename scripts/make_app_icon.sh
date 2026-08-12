#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
RESOURCE_DIR="$PROJECT_ROOT/Sources/AELanguageSwitcherApp/Resources"
SOURCE_PNG="$RESOURCE_DIR/AppIconSource.png"
OUTPUT_ICNS="$RESOURCE_DIR/AppIcon.icns"

width="$(sips -g pixelWidth "$SOURCE_PNG" | awk '/pixelWidth:/ { print $2 }')"
height="$(sips -g pixelHeight "$SOURCE_PNG" | awk '/pixelHeight:/ { print $2 }')"

if [[ -z "$width" || -z "$height" || "$width" != "$height" ]]; then
    echo "App icon source must be a square image." >&2
    exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ae-language-switcher-icon.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT
ICONSET_DIR="$TEMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

render_icon() {
    local size="$1"
    local filename="$2"
    sips -z "$size" "$size" "$SOURCE_PNG" --out "$ICONSET_DIR/$filename" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
echo "Generated app icon: $OUTPUT_ICNS"
