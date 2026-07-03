#!/usr/bin/env bash
set -euo pipefail

APP_NAME="E2BBar"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SVG_PATH="$ROOT_DIR/Resources/${APP_NAME}Icon.svg"
ICNS_PATH="$ROOT_DIR/Resources/${APP_NAME}Icon.icns"
TMP_DIR="$(mktemp -d)"
ICONSET_DIR="$TMP_DIR/${APP_NAME}Icon.iconset"
SOURCE_PNG="$TMP_DIR/${APP_NAME}Icon-1024.png"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "Missing rsvg-convert. Install librsvg, for example: brew install librsvg" >&2
  exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
  echo "Missing sips. This script must run on macOS." >&2
  exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
  echo "Missing iconutil. This script must run on macOS." >&2
  exit 1
fi

if [[ ! -f "$SVG_PATH" ]]; then
  echo "Missing SVG source: $SVG_PATH" >&2
  exit 1
fi

mkdir -p "$ICONSET_DIR"
rsvg-convert --width 1024 --height 1024 --format png "$SVG_PATH" > "$SOURCE_PNG"

make_icon() {
  local size="$1"
  local scale="$2"
  local pixels="$3"
  sips -s format png -z "$pixels" "$pixels" "$SOURCE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}${scale}.png" >/dev/null
}

make_icon 16 "" 16
make_icon 16 "@2x" 32
make_icon 32 "" 32
make_icon 32 "@2x" 64
make_icon 128 "" 128
make_icon 128 "@2x" 256
make_icon 256 "" 256
make_icon 256 "@2x" 512
make_icon 512 "" 512
make_icon 512 "@2x" 1024

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
echo "Created $ICNS_PATH"
