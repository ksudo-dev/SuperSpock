#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-release}"
DESTINATION="${2:-$ROOT/build}"
APP="$DESTINATION/SuperSpock.app"

cd "$ROOT"
swift build -c "$CONFIGURATION"
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/SuperSpock" "$APP/Contents/MacOS/SuperSpock"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod 755 "$APP/Contents/MacOS/SuperSpock"
codesign --force --deep --sign - "$APP"
echo "$APP"
