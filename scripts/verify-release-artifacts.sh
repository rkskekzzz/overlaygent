#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Overlaygent"
VERSION="${OVERLAYGENT_RELEASE_VERSION:-0.1.0}"
BUILD_NUMBER="${OVERLAYGENT_RELEASE_BUILD:-1}"
APP_DIR="${OVERLAYGENT_RELEASE_APP_PATH:-$ROOT_DIR/.build/release-app/$APP_NAME.app}"
DMG_PATH="${OVERLAYGENT_RELEASE_DMG_PATH:-$ROOT_DIR/.build/dist/$APP_NAME-$VERSION+$BUILD_NUMBER.dmg}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "error: app bundle not found: $APP_DIR" >&2
  exit 66
fi

codesign --verify --deep --strict --verbose=4 "$APP_DIR"
codesign --display --verbose=4 "$APP_DIR"
spctl --assess --type execute --verbose=4 "$APP_DIR"

if [[ -f "$DMG_PATH" ]]; then
  codesign --verify --verbose=4 "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
  if xcrun stapler validate "$DMG_PATH"; then
    echo "stapler validation passed: $DMG_PATH"
  else
    echo "warning: stapler validation failed; notarization may not have been completed yet." >&2
  fi
  shasum -a 256 "$DMG_PATH"
else
  echo "warning: DMG not found, skipped DMG verification: $DMG_PATH" >&2
fi
