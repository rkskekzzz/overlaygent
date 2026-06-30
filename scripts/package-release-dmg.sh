#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Overlaygent"
VERSION="${OVERLAYGENT_RELEASE_VERSION:-0.1.0}"
BUILD_NUMBER="${OVERLAYGENT_RELEASE_BUILD:-1}"
APP_DIR="${1:-$ROOT_DIR/.build/release-app/$APP_NAME.app}"
DIST_DIR="$ROOT_DIR/.build/dist"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION+$BUILD_NUMBER.dmg"

if [[ ! -d "$APP_DIR" ]]; then
  echo "error: app bundle not found: $APP_DIR" >&2
  echo "Run scripts/build-release-app.sh first, or pass an app bundle path." >&2
  exit 66
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

IDENTITY="${OVERLAYGENT_CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -n 1)"
fi

if [[ -n "$IDENTITY" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
echo "$DMG_PATH"
