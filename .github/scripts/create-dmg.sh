#!/usr/bin/env bash

set -euo pipefail

APP_PATH="${1:?App bundle path is required.}"
DMG_PATH="${2:?Output dmg path is required.}"
VOLUME_NAME="${3:-$(basename "$APP_PATH" .app)}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$DMG_PATH")"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "${MACOS_CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$MACOS_CODESIGN_IDENTITY" "$DMG_PATH"
fi
