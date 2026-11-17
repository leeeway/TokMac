#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

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

echo "🎉 Success! DMG installer created at: ${DMG_PATH}"
ls -lh "${DMG_PATH}"
