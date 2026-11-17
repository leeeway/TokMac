#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -module-cache-path "${TMPDIR:-/tmp}/tokmac-test-module-cache" \
    Sources/TokMacCore/DownloadFile.swift tests/DownloadFileTests.swift -o "$TEST_DIR/download-tests"
"$TEST_DIR/download-tests"
if [[ "${1:-}" == "--webkit" ]]; then
    swiftc -module-cache-path "${TMPDIR:-/tmp}/tokmac-test-module-cache" \
        Sources/TokMacCore/DownloadFile.swift tests/NativeBlobSmoke.swift -o "$TEST_DIR/blob-test"
    "$TEST_DIR/blob-test"
    swiftc -module-cache-path "${TMPDIR:-/tmp}/tokmac-test-module-cache" \
        Sources/TokMac/PopupWindowStore.swift Sources/TokMac/ApplicationMenus.swift \
        Sources/TokMac/MainWindowController.swift tests/AppKitRegression.swift -o "$TEST_DIR/appkit-test"
    "$TEST_DIR/appkit-test"
fi
