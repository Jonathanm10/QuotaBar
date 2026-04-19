#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="QuotaBar"
APP_DIR="$ROOT_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
BUILD_DIR="$ROOT_DIR/.build/apple/Products/Release"
ARTIFACTS_DIR="$ROOT_DIR/.build/release-art"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

swift build -c release --arch arm64 --arch x86_64

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR" "$ARTIFACTS_DIR"

swift "$ROOT_DIR/Scripts/render_release_art.swift" "$ARTIFACTS_DIR"

cp "$BUILD_DIR/QuotaBar" "$MACOS_DIR/QuotaBar"
chmod +x "$MACOS_DIR/QuotaBar"

RESOURCE_BUNDLE="$BUILD_DIR/QuotaBar_QuotaBarApp.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Missing SwiftPM resource bundle: $RESOURCE_BUNDLE" >&2
  exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"

if [[ -f "$ARTIFACTS_DIR/QuotaBar.icns" ]]; then
  cp "$ARTIFACTS_DIR/QuotaBar.icns" "$RESOURCES_DIR/QuotaBar.icns"
fi

if [[ -d "$BUILD_DIR/PackageFrameworks" ]] && find "$BUILD_DIR/PackageFrameworks" -mindepth 1 -print -quit >/dev/null; then
  cp -R "$BUILD_DIR/PackageFrameworks/." "$FRAMEWORKS_DIR/"
fi

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>QuotaBar</string>
  <key>CFBundleExecutable</key>
  <string>QuotaBar</string>
  <key>CFBundleIconFile</key>
  <string>QuotaBar</string>
  <key>CFBundleIdentifier</key>
  <string>com.jonathan.QuotaBar</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>QuotaBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

SMOKE_SNAPSHOT="$ARTIFACTS_DIR/package-smoke.png"
rm -f "$SMOKE_SNAPSHOT"
"$MACOS_DIR/QuotaBar" --snapshot "$SMOKE_SNAPSHOT" >/dev/null
if [[ ! -s "$SMOKE_SNAPSHOT" ]]; then
  echo "Packaged app smoke test failed: snapshot not created" >&2
  exit 1
fi

echo "Packaged $APP_DIR (version $VERSION, build $BUILD_NUMBER)"
