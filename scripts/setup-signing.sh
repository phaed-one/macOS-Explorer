#!/bin/zsh
set -euo pipefail
umask 077

IDENTITY="Explorer Local Code Signing"
KEYCHAIN="$(security default-keychain -d user | tr -d '"' | sed 's/^[[:space:]]*//')"
if [[ "$(security find-identity -v -p codesigning)" == *"\"$IDENTITY\""* ]]; then
    echo "Signing identity already available: $IDENTITY"
    exit 0
fi
if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "The certificate already exists but is not a valid signing identity. Repair its trust/private key in Keychain Access instead of replacing it." >&2
    exit 1
fi

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/explorer-signing.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
    -subj "/CN=$IDENTITY/" \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext 'extendedKeyUsage=critical,codeSigning' \
    -keyout "$TEMP_DIR/key.pem" -out "$TEMP_DIR/cert.pem" 2>"$TEMP_DIR/generation.log"
# Use PKCS#12 algorithms supported by macOS Keychain. The temporary bundle is
# readable only by this user and is deleted immediately after installation.
BUNDLE_PASSWORD=$(openssl rand -hex 32)
/usr/bin/openssl pkcs12 -export -inkey "$TEMP_DIR/key.pem" -in "$TEMP_DIR/cert.pem" \
    -name "$IDENTITY" \
    -passout stdin -out "$TEMP_DIR/identity.p12" <<< "$BUNDLE_PASSWORD"
security import "$TEMP_DIR/identity.p12" -k "$KEYCHAIN" -f pkcs12 -P "$BUNDLE_PASSWORD" -T /usr/bin/codesign
# Trust this certificate only for code signing, in this user's trust store.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TEMP_DIR/cert.pem"
if [[ "$(security find-identity -v -p codesigning)" != *"\"$IDENTITY\""* ]]; then
    echo "The certificate was installed, but macOS does not yet recognize it for code signing. Check its trust in Keychain Access." >&2
    exit 1
fi
echo "Installed persistent signing identity: $IDENTITY"
echo "Keep this identity in your Keychain; future builds reuse it."
