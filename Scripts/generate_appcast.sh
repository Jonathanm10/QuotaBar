#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="QuotaBar"
VERSION="${VERSION:-0.0.0-dev}"
TAG="${TAG:-v${VERSION}}"
DMG="${DMG:-$ROOT_DIR/${APP_NAME}-${VERSION}.dmg}"
SPARKLE_PRIVATE_ED_KEY="${SPARKLE_PRIVATE_ED_KEY:-}"
GENERATE_APPCAST="${GENERATE_APPCAST:-$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/Jonathanm10/QuotaBar/releases/download/${TAG}/}"
PRODUCT_LINK="${PRODUCT_LINK:-https://github.com/Jonathanm10/QuotaBar}"
OUTPUT_APPCAST="${OUTPUT_APPCAST:-$ROOT_DIR/appcast.xml}"

if [[ ! -f "$DMG" ]]; then
  echo "Missing DMG: $DMG" >&2
  exit 1
fi

if [[ -z "$SPARKLE_PRIVATE_ED_KEY" ]]; then
  echo "SPARKLE_PRIVATE_ED_KEY is required to sign the Sparkle appcast" >&2
  exit 1
fi

if [[ ! -x "$GENERATE_APPCAST" ]]; then
  echo "Missing Sparkle generate_appcast tool: $GENERATE_APPCAST" >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-appcast.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

ARCHIVE_NAME="${APP_NAME}-${VERSION}.dmg"
cp "$DMG" "$STAGING_DIR/$ARCHIVE_NAME"

cat > "$STAGING_DIR/${APP_NAME}-${VERSION}.md" <<EOF
# ${APP_NAME} ${VERSION}

See the GitHub release for details:
https://github.com/Jonathanm10/QuotaBar/releases/tag/${TAG}
EOF

printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$GENERATE_APPCAST" \
  --ed-key-file - \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --link "$PRODUCT_LINK" \
  --embed-release-notes \
  -o "$OUTPUT_APPCAST" \
  "$STAGING_DIR"

echo "Created $OUTPUT_APPCAST"
