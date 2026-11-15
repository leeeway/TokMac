#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "🔨 Building TokMac (Release mode)..."
swift build -c release

APP_NAME="TokMac.app"
APP_DIR="./build/${APP_NAME}"
BINARY_PATH=".build/release/TokMac"

echo "📦 Creating macOS App Bundle at ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp Resources/Info.plist "${APP_DIR}/Contents/"
cp Resources/AppIcon.icns "${APP_DIR}/Contents/Resources/"
cp "${BINARY_PATH}" "${APP_DIR}/Contents/MacOS/TokMac"

chmod +x "${APP_DIR}/Contents/MacOS/TokMac"

echo "🔏 Ad-hoc code signing..."
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true

echo "📲 Installing to /Applications..."
rm -rf "/Applications/${APP_NAME}"
cp -R "${APP_DIR}" "/Applications/${APP_NAME}"
killall Dock 2>/dev/null || true

echo "✅ TokMac.app successfully installed to /Applications!"
echo "🚀 Available now in Launchpad (启动台) & Spotlight!"
