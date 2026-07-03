#!/usr/bin/env bash
set -euo pipefail

APP_NAME="E2BBar"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
DMG_PATH="$ROOT_DIR/build/$APP_NAME.dmg"
STAGING_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [[ ! -d "$APP_DIR" ]]; then
  "$ROOT_DIR/Scripts/package_app.sh" release
fi

mkdir -p "$STAGING_DIR/$APP_NAME"
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/$APP_NAME/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR/$APP_NAME" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"
