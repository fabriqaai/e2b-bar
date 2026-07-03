#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"
APP_NAME="E2BBar"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$(cd "$ROOT_DIR" && swift build --show-bin-path -c "$CONFIGURATION")"
EXECUTABLE="$BIN_DIR/$APP_NAME"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
ICON_SOURCE="$ROOT_DIR/Resources/${APP_NAME}Icon.icns"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Missing executable: $EXECUTABLE" >&2
  exit 1
fi

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing app icon: $ICON_SOURCE" >&2
  echo "Run ./Scripts/build_icon.sh to regenerate it from Resources/${APP_NAME}Icon.svg." >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ICON_SOURCE" "$APP_DIR/Contents/Resources/${APP_NAME}Icon.icns"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "Created $APP_DIR"
