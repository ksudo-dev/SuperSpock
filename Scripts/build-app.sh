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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_PATH/SuperSpock" "$APP/Contents/MacOS/SuperSpock"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -e "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
# The stasel/WebRTC binary framework is linked via @rpath; ship it inside the
# bundle so the app runs anywhere, not just next to the SwiftPM build dir.
cp -R "$BIN_PATH/WebRTC.framework" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/SuperSpock"
chmod 755 "$APP/Contents/MacOS/SuperSpock"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
echo "$APP"
