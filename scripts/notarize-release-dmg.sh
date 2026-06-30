#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Overlaygent"
VERSION="${OVERLAYGENT_RELEASE_VERSION:-0.1.0}"
BUILD_NUMBER="${OVERLAYGENT_RELEASE_BUILD:-1}"
DMG_PATH="${1:-$ROOT_DIR/.build/dist/$APP_NAME-$VERSION+$BUILD_NUMBER.dmg}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "error: DMG not found: $DMG_PATH" >&2
  echo "Run scripts/package-release-dmg.sh first, or pass a DMG path." >&2
  exit 66
fi

if [[ -n "${OVERLAYGENT_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$OVERLAYGENT_NOTARY_PROFILE" \
    --wait
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
else
  echo "error: notarization credentials are not configured." >&2
  echo "Set OVERLAYGENT_NOTARY_PROFILE, or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD." >&2
  exit 67
fi

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

echo "$DMG_PATH"
