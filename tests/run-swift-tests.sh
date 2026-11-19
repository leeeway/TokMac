#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
MODULE_CACHE="${TMPDIR:-/tmp}/tokmac-test-module-cache"
swiftc -module-cache-path "$MODULE_CACHE" \
    Sources/TokMacCore/*.swift tests/DownloadFileTests.swift -o "$TEST_DIR/download-tests"
"$TEST_DIR/download-tests"
if [[ "${1:-}" == "--webkit" ]]; then
    swiftc -module-cache-path "$MODULE_CACHE" \
        Sources/TokMacCore/DownloadFile.swift Sources/TokMacCore/VideoContainer.swift tests/NativeBlobSmoke.swift -o "$TEST_DIR/blob-test"
    "$TEST_DIR/blob-test"
    swiftc -module-cache-path "$MODULE_CACHE" -emit-module -module-name TokMacCore \
        -emit-module-path "$TEST_DIR/TokMacCore.swiftmodule" \
        -emit-library -static Sources/TokMacCore/*.swift -o "$TEST_DIR/libTokMacCore.a"
    swiftc -module-cache-path "$MODULE_CACHE" -I "$TEST_DIR" -L "$TEST_DIR" -lTokMacCore \
        Sources/TokMac/PopupWindowStore.swift Sources/TokMac/ApplicationMenus.swift \
        Sources/TokMac/MainWindowController.swift Sources/TokMac/DownloadHUDView.swift \
        Sources/TokMac/WatchLaterWindow.swift Sources/TokMac/WatchLaterThumbnails.swift \
        tests/AppKitRegression.swift -o "$TEST_DIR/appkit-test"
    "$TEST_DIR/appkit-test"
fi
