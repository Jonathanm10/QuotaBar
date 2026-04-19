#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="QuotaBar"
APP_DIR="$ROOT_DIR/${APP_NAME}.app"
ARTIFACTS_DIR="$ROOT_DIR/.build/release-art"
VERSION="${VERSION:-0.0.0-dev}"
VOLUME_NAME="${APP_NAME}"
OUTPUT_DMG="${OUTPUT_DMG:-$ROOT_DIR/${APP_NAME}-${VERSION}.dmg}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing app bundle: $APP_DIR" >&2
  exit 1
fi

mkdir -p "$ARTIFACTS_DIR"
swift "$ROOT_DIR/Scripts/render_release_art.swift" "$ARTIFACTS_DIR"

BACKGROUND_FILE="$ARTIFACTS_DIR/dmg-background.png"
if [[ ! -f "$BACKGROUND_FILE" ]]; then
  echo "Missing DMG background art: $BACKGROUND_FILE" >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-dmg.XXXXXX")"
RW_DMG="$STAGING_DIR/${APP_NAME}-${VERSION}-rw.dmg"
SOURCE_DIR="$STAGING_DIR/source"
DEVICE=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$SOURCE_DIR/.background"
cp -R "$APP_DIR" "$SOURCE_DIR/"
ln -s /Applications "$SOURCE_DIR/Applications"
cp "$BACKGROUND_FILE" "$SOURCE_DIR/.background/background.png"

rm -f "$OUTPUT_DMG"
hdiutil create \
  -quiet \
  -srcfolder "$SOURCE_DIR" \
  -volname "$VOLUME_NAME" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_DMG"

DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | awk '/Apple_HFS/ {print $1; exit}')"

osascript <<EOF
tell application "Finder"
  tell disk "${VOLUME_NAME}"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 140, 840, 580}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 14
    set background picture of viewOptions to file ".background:background.png"
    set position of item "${APP_NAME}.app" of container window to {180, 235}
    set position of item "Applications" of container window to {520, 235}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF

sync
hdiutil detach "$DEVICE" -quiet
DEVICE=""

hdiutil convert \
  -quiet \
  "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$OUTPUT_DMG"

echo "Created $OUTPUT_DMG"
