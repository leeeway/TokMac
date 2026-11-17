#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "🔨 Building TokMac (Release mode)..."
APP_VERSION="${APP_VERSION:-$(cat VERSION)}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid APP_VERSION: ${APP_VERSION}" >&2
    exit 1
fi
BINARIES=()
# Build each architecture with SwiftPM's native build system. Multi-architecture
# --arch builds require full Xcode; separate triples also work with Command Line Tools.
for architecture in arm64 x86_64; do
    BUILD_ARGS=(-c release --triple "${architecture}-apple-macosx")
    swift build "${BUILD_ARGS[@]}"
    BINARY_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
    BINARIES+=("${BINARY_DIR}/TokMac")
done

APP_NAME="TokMac.app"
APP_DIR="./build/${APP_NAME}"

echo "📦 Creating macOS App Bundle at ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp Resources/Info.plist "${APP_DIR}/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${APP_VERSION}" "${APP_DIR}/Contents/Info.plist"
cp Resources/AppIcon.icns "${APP_DIR}/Contents/Resources/"
lipo -create "${BINARIES[@]}" -output "${APP_DIR}/Contents/MacOS/TokMac"
for bundle in "${BINARY_DIR}"/*.bundle; do
    if [[ -d "$bundle" ]]; then
        cp -R "$bundle" "${APP_DIR}/Contents/Resources/"
    fi
done

chmod +x "${APP_DIR}/Contents/MacOS/TokMac"

echo "🔏 Ad-hoc code signing..."
codesign --force --deep --sign - "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"

echo "✅ Built ${APP_DIR} (${APP_VERSION}, Universal). Drag it into Applications to install."
