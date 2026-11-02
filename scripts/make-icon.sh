#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from the SwiftUI mascot artwork (AppIconArtwork).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c debug
ICONSET="$(mktemp -d)/AppIcon.iconset"
"$(swift build -c debug --show-bin-path)/Notchy" --render-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
