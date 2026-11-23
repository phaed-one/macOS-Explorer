#!/bin/zsh
# Build Explorer.app from source in one step. Needs only Xcode or its command-line
# tools: no signing keys, no version bump, no release files.
#
#   zsh scripts/build-from-source.sh            # builds build/Explorer.app
#   zsh scripts/build-from-source.sh --install  # also replaces /Applications/Explorer.app
set -euo pipefail
cd "${0:A:h:h}"

usage="Usage: zsh scripts/build-from-source.sh [--install]"
INSTALL=false
case "${1:-}" in
    "") ;;
    --install) INSTALL=true ;;
    -h|--help) echo "$usage"; exit 0 ;;
    *) echo "$usage" >&2; exit 1 ;;
esac
if ! command -v swift >/dev/null 2>&1; then
    echo "Swift is missing. Install Xcode 16 or later, or run: xcode-select --install" >&2
    exit 1
fi

echo "Building Explorer…"
swift build -c release --product Explorer
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="$PWD/build/Explorer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$BIN_DIR/Explorer" "$APP/Contents/MacOS/Explorer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# A persistent identity keeps macOS permissions (such as Full Disk Access) across rebuilds.
# Without one, sign ad hoc: the app runs, but macOS asks for permissions again after each build.
IDENTITY="Explorer Local Code Signing"
if [[ "$(security find-identity -v -p codesigning)" == *"\"$IDENTITY\""* ]]; then
    codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
    SIGNED_WITH="$IDENTITY"
else
    codesign --force --sign - "$APP"
    SIGNED_WITH="ad hoc (run zsh scripts/setup-signing.sh once to keep permissions across rebuilds)"
fi
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
echo "Built $APP ($VERSION), signed $SIGNED_WITH"

if ! $INSTALL; then
    echo "Run it with: open \"$APP\""
    exit 0
fi
if pgrep -x Explorer >/dev/null; then
    echo "Quitting Explorer…"
    osascript -e 'tell application id "local.pathfind.app" to quit' >/dev/null 2>&1 || true
    for _ in {1..40}; do pgrep -x Explorer >/dev/null || break; sleep 0.25; done
    pkill -x Explorer 2>/dev/null || true
fi
rm -rf /Applications/Explorer.app
ditto "$APP" /Applications/Explorer.app
echo "Installed /Applications/Explorer.app"
open /Applications/Explorer.app
