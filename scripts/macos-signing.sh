#!/usr/bin/env bash
# Shared by the app and DMG builders. Never put credentials in this file.
export TOKMAC_SIGNING_MODE="${TOKMAC_SIGNING_MODE:-development}"

validate_signing_configuration() {
    case "$TOKMAC_SIGNING_MODE" in
        development) ;;
        distribution)
            if [[ -z "${CODE_SIGN_IDENTITY:-}" ]]; then
                echo "Distribution requires CODE_SIGN_IDENTITY (Developer ID Application)." >&2
                return 1
            fi
            if [[ -z "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
                if [[ ! -s "${NOTARY_KEY_PATH:-}" || -z "${NOTARY_KEY_ID:-}" || -z "${NOTARY_ISSUER_ID:-}" ]]; then
                    echo "Distribution requires a notarytool keychain profile or App Store Connect API key configuration." >&2
                    return 1
                fi
            fi
            ;;
        *) echo "Unknown TOKMAC_SIGNING_MODE: $TOKMAC_SIGNING_MODE" >&2; return 1 ;;
    esac
}

sign_distribution_file() {
    local target="$1"
    local signing_args=(--force --timestamp --sign "$CODE_SIGN_IDENTITY")
    if [[ "$target" == *.app ]]; then signing_args+=(--options runtime); fi
    if [[ -n "${CODE_SIGN_KEYCHAIN:-}" ]]; then signing_args+=(--keychain "$CODE_SIGN_KEYCHAIN"); fi
    codesign "${signing_args[@]}" "$target"
    codesign --verify --deep --strict "$target"
    local signature
    signature="$(codesign -dv --verbose=2 "$target" 2>&1)"
    if [[ "$signature" != *"Authority=Developer ID Application:"* ]]; then
        echo "Distribution must use a Developer ID Application certificate." >&2
        return 1
    fi
}

notarize_file() {
    local target="$1"
    local auth=()
    if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
        auth=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
    else
        auth=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
    fi
    local result="${target}.notary-result.json"
    xcrun notarytool submit "$target" "${auth[@]}" --wait --output-format json > "$result"
    python3 - "$result" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    result = json.load(stream)
if result.get('status') != 'Accepted':
    raise SystemExit('Apple notarization was not accepted; inspect ' + sys.argv[1])
PY
}
