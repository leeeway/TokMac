#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

source ./scripts/macos-signing.sh
validate_signing_configuration
rm -f ./build/macos-release-status.json

echo "🔨 1. Building TokMac Application Bundle..."
./build_app.sh

APP_VERSION="${APP_VERSION:-$(cat VERSION)}"
DMG_NAME="TokMac-${APP_VERSION}.dmg"
DMG_PATH="./build/${DMG_NAME}"
STAGING_DIR="./build/dmg_staging"

echo "📦 2. Preparing DMG Staging Directory..."
rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"
trap 'rm -rf "${STAGING_DIR}"' EXIT

if [[ "$TOKMAC_SIGNING_MODE" == distribution ]]; then
    echo "🔏 Notarizing and stapling the app..."
    APP_ARCHIVE="./build/TokMac-notarization.zip"
    ditto -c -k --keepParent ./build/TokMac.app "$APP_ARCHIVE"
    notarize_file "$APP_ARCHIVE"
    xcrun stapler staple ./build/TokMac.app
    xcrun stapler validate ./build/TokMac.app
    spctl --assess --type execute --verbose ./build/TokMac.app
    rm "$APP_ARCHIVE"
fi

# Copy TokMac.app
cp -R "./build/TokMac.app" "${STAGING_DIR}/"

# Create symlink to /Applications for standard drag-to-install experience
ln -s /Applications "${STAGING_DIR}/Applications"

echo "💿 3. Creating compressed DMG image..."
hdiutil create \
    -volname "TokMac" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

rm -rf "${STAGING_DIR}"

if [[ "$TOKMAC_SIGNING_MODE" == distribution ]]; then
    echo "🔏 Signing, notarizing and stapling the DMG..."
    sign_distribution_file "$DMG_PATH"
    notarize_file "$DMG_PATH"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
fi

python3 - "$DMG_PATH" "$APP_VERSION" "$TOKMAC_SIGNING_MODE" <<'STATUS_PY'
import hashlib, json, sys
from pathlib import Path
path, version, mode = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
status = dict(file=path.name, version=version, signing_mode=mode,
              notarized=mode == 'distribution', sha256=hashlib.sha256(path.read_bytes()).hexdigest())
(path.parent / 'macos-release-status.json').write_text(json.dumps(status, indent=2) + '\n')
STATUS_PY

echo "🎉 Success! DMG installer created at: ${DMG_PATH}"
ls -lh "${DMG_PATH}"
