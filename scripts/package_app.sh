#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
OUTPUTS_DIR="$PROJECT_ROOT/outputs"
APP_BASENAME="AE中英文切换器.app"
APP_PATH="$OUTPUTS_DIR/$APP_BASENAME"
EXECUTABLE_SOURCE="$PROJECT_ROOT/.build/release/AELanguageSwitcherApp"
PLIST_SOURCE="$PROJECT_ROOT/Sources/AELanguageSwitcherApp/Resources/Info.plist"
ICON_SCRIPT="$PROJECT_ROOT/scripts/make_app_icon.sh"
ICON_SOURCE="$PROJECT_ROOT/Sources/AELanguageSwitcherApp/Resources/AppIcon.icns"

bash "$ICON_SCRIPT"
xcrun swift build -c release --package-path "$PROJECT_ROOT"

mkdir -p "$OUTPUTS_DIR"
RESOLVED_OUTPUTS_DIR="$(cd "$OUTPUTS_DIR" && pwd -P)"

if [[ "$RESOLVED_OUTPUTS_DIR" != "$PROJECT_ROOT/outputs" ]]; then
    echo "Refusing to package outside the project outputs directory." >&2
    exit 1
fi

if [[ "$(dirname "$APP_PATH")" != "$RESOLVED_OUTPUTS_DIR" ]]; then
    echo "Refusing to remove an app whose parent is not the validated outputs directory." >&2
    exit 1
fi

if [[ "$(basename "$APP_PATH")" != "$APP_BASENAME" ]]; then
    echo "Refusing to remove an app with an unexpected basename." >&2
    exit 1
fi

if [[ -e "$APP_PATH" || -L "$APP_PATH" ]]; then
    rm -rf -- "$APP_PATH"
fi

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
install -m 755 "$EXECUTABLE_SOURCE" "$APP_PATH/Contents/MacOS/AE中英文切换器"
install -m 644 "$PLIST_SOURCE" "$APP_PATH/Contents/Info.plist"
install -m 644 "$ICON_SOURCE" "$APP_PATH/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "Packaged app: $APP_PATH"
