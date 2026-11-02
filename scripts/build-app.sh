#!/usr/bin/env bash
# Builds build/Notchy.app (Apple Silicon). Usage: scripts/build-app.sh [debug|release]
# Set CODESIGN_IDENTITY="Developer ID Application: …" to sign for distribution; defaults to ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="Notchy"
APP="build/${APP_NAME}.app"

swift build -c "$CONFIG" --arch arm64
BIN_DIR="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime \
  --entitlements Resources/Notchy.entitlements \
  --sign "${CODESIGN_IDENTITY:--}" \
  "$APP"

echo "Built $APP"
