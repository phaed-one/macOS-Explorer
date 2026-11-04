#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

# Serialize packaging so simultaneous builds cannot publish the same version.
mkdir -p dist
LOCK="$PWD/dist/.build-lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "Another app build is running (lock: $LOCK)." >&2
    exit 1
fi
STAGING=""
cleanup() {
    [[ -z "$STAGING" ]] || rm -rf "$STAGING"
    rmdir "$LOCK"
}
trap cleanup EXIT

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ! "$BUILD" =~ '^[0-9]+$' ]]; then
    echo "Expected a major.minor.patch version and an integer build number in Resources/Info.plist." >&2
    exit 1
fi
PARTS=("${(@s:.:)VERSION}")
NEXT_VERSION="${PARTS[1]}.${PARTS[2]}.$(( PARTS[3] + 1 ))"
NEXT_BUILD=$(( BUILD + 1 ))
ZIP="$PWD/dist/Explorer-${NEXT_VERSION}.zip"
if [[ -e "$ZIP" ]]; then
    echo "Archive already exists: $ZIP. Update Resources/Info.plist before rebuilding." >&2
    exit 1
fi

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
STAGING=$(mktemp -d "$PWD/dist/.package.XXXXXX")
APP="$STAGING/Explorer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Explorer" "$APP/Contents/MacOS/Explorer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEXT_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT_BUILD" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGING/Explorer-${NEXT_VERSION}.zip"
/usr/bin/unzip -tq "$STAGING/Explorer-${NEXT_VERSION}.zip"

# Commit the version only after compilation, signing, and ZIP validation pass.
cp "$APP/Contents/Info.plist" "$STAGING/Info.plist"
rm -rf "$PWD/dist/Explorer.app"
mv "$APP" "$PWD/dist/Explorer.app"
mv "$STAGING/Explorer-${NEXT_VERSION}.zip" "$ZIP"
mv "$STAGING/Info.plist" Resources/Info.plist
echo "Built $PWD/dist/Explorer.app ($NEXT_VERSION, build $NEXT_BUILD)"
echo "Packaged $ZIP"
