#!/usr/bin/env bash
set -euo pipefail
umask 077
for name in MACOS_CERTIFICATE_P12 MACOS_CERTIFICATE_PASSWORD MACOS_SIGNING_IDENTITY APPLE_NOTARY_KEY_P8 APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID; do
    if [[ -z "${!name:-}" ]]; then
        echo "Missing signing secret: $name. Configure Developer ID signing and notarization before distribution." >&2
        exit 1
    fi
done
SIGNING_DIR="${RUNNER_TEMP:?}/tokmac-signing"
mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"
printf '%s' "$MACOS_CERTIFICATE_P12" | base64 --decode > "$SIGNING_DIR/certificate.p12"
printf '%s' "$APPLE_NOTARY_KEY_P8" > "$SIGNING_DIR/notary.p8"
chmod 600 "$SIGNING_DIR/certificate.p12" "$SIGNING_DIR/notary.p8"
KEYCHAIN="$SIGNING_DIR/signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$SIGNING_DIR/certificate.p12" -k "$KEYCHAIN" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
rm "$SIGNING_DIR/certificate.p12"
{
    echo 'TOKMAC_SIGNING_MODE=distribution'
    echo "CODE_SIGN_IDENTITY=$MACOS_SIGNING_IDENTITY"
    echo "CODE_SIGN_KEYCHAIN=$KEYCHAIN"
    echo "NOTARY_KEY_PATH=$SIGNING_DIR/notary.p8"
    echo "NOTARY_KEY_ID=$APPLE_NOTARY_KEY_ID"
    echo "NOTARY_ISSUER_ID=$APPLE_NOTARY_ISSUER_ID"
} >> "${GITHUB_ENV:?}"
