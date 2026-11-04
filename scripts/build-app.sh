#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

SIGNING_IDENTITY="Explorer Local Code Signing"
if [[ "$(security find-identity -v -p codesigning)" != *"\"$SIGNING_IDENTITY\""* ]]; then
    echo "Persistent signing identity missing. Run: zsh scripts/setup-signing.sh" >&2
    exit 1
fi

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
NEXT_BUILD=$(( BUILD + 1 ))
case "${1:-}" in
    "") NEXT_VERSION="${PARTS[1]}.${PARTS[2]}.$(( PARTS[3] + 1 ))"; ARCHIVE_NAME="Explorer-${NEXT_VERSION}.zip" ;;
    --same-version) NEXT_VERSION="$VERSION"; ARCHIVE_NAME="Explorer-${NEXT_VERSION}-build${NEXT_BUILD}.zip" ;;
    --version)
        NEXT_VERSION="${2:-}"
        if [[ ! "$NEXT_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
            echo "--version requires major.minor.patch" >&2; exit 1
        fi
        ARCHIVE_NAME="Explorer-${NEXT_VERSION}.zip"
        if [[ -e "$PWD/dist/$ARCHIVE_NAME" ]]; then
            ARCHIVE_NAME="Explorer-${NEXT_VERSION}-build${NEXT_BUILD}.zip"
        fi
        ;;
    *) echo "Usage: zsh scripts/build-app.sh [--same-version | --version X.Y.Z]" >&2; exit 1 ;;
esac
ZIP="$PWD/dist/$ARCHIVE_NAME"
if [[ -e "$ZIP" ]]; then
    echo "Archive already exists: $ZIP. Update Resources/Info.plist before rebuilding." >&2
    exit 1
fi

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
PUBLIC_KEY=$("$PWD/.build/artifacts/sparkle/Sparkle/bin/generate_keys" --account local.pathfind.app -p)
EXPECTED_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)
if [[ "$PUBLIC_KEY" != "$EXPECTED_KEY" ]]; then
    echo "The update signing key does not match this app. Restore the original Sparkle key in your Keychain." >&2
    exit 1
fi
STAGING=$(mktemp -d "$PWD/dist/.package.XXXXXX")
APP="$STAGING/Explorer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$BIN_DIR/Explorer" "$APP/Contents/MacOS/Explorer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEXT_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT_BUILD" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGING/$ARCHIVE_NAME"
/usr/bin/unzip -tq "$STAGING/$ARCHIVE_NAME"
python3 scripts/create-appcast.py "$STAGING/$ARCHIVE_NAME" "$APP/Contents/Info.plist" "$STAGING"

# Commit the version only after compilation, signing, and ZIP validation pass.
cp "$APP/Contents/Info.plist" "$STAGING/Info.plist"
rm -rf "$PWD/dist/Explorer.app"
mv "$APP" "$PWD/dist/Explorer.app"
mv "$STAGING/$ARCHIVE_NAME" "$ZIP"
mv "$STAGING/appcast.xml" "$PWD/dist/appcast.xml"
mv "$STAGING/release.json" "$PWD/dist/release.json"
mv "$STAGING/Info.plist" Resources/Info.plist
echo "Built $PWD/dist/Explorer.app ($NEXT_VERSION, build $NEXT_BUILD)"
echo "Packaged $ZIP"
