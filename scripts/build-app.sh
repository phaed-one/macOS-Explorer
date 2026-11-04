#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/Explorer.app"
if [[ -d "$PWD/dist/Pathfind.app" && ! -d "$APP" ]]; then
    mv "$PWD/dist/Pathfind.app" "$APP"
fi
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Explorer" "$APP/Contents/MacOS/Explorer"
rm -f "$APP/Contents/MacOS/Pathfind"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
