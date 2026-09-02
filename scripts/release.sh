#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/Thermal Cam.app"
VERSION="${1:-}"

if ! [[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' ]]; then
    echo "Usage: $0 <version>, for example: $0 0.1.0" >&2
    exit 1
fi

SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: John Boiles (62G85M9ZN5)}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

APP_VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    "$PROJECT_DIR/scripts/build-app.sh"

SIGNING_AUTHORITY="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1 | awk -F= '/^Authority=Developer ID Application:/ { print $2; exit }')"
if [[ -z "$SIGNING_AUTHORITY" ]]; then
    echo "The release app is not signed with a Developer ID Application certificate." >&2
    exit 1
fi

ARCHS="$(lipo -archs "$APP_DIR/Contents/MacOS/ThermalCam")"
if [[ "$ARCHS" == *" "* ]]; then
    ARCH_LABEL="universal"
else
    ARCH_LABEL="$ARCHS"
fi

ARCHIVE_BASENAME="Thermal-Cam-${VERSION}-macOS-${ARCH_LABEL}.zip"
FINAL_ARCHIVE="$DIST_DIR/$ARCHIVE_BASENAME"
CHECKSUM_FILE="$FINAL_ARCHIVE.sha256"
NOTARY_RESULT="$DIST_DIR/notarization-${VERSION}.json"
NOTARY_WORK="$(mktemp -d "${TMPDIR:-/tmp}/thermal-cam-notary.XXXXXX")"
UPLOAD_ARCHIVE="$NOTARY_WORK/$ARCHIVE_BASENAME"
trap 'rm -rf -- "$NOTARY_WORK"' EXIT

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$UPLOAD_ARCHIVE"

NOTARY_ARGS=()
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    NOTARY_ARGS+=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
    NOTARY_ARGS+=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
    echo "Provide NOTARY_KEYCHAIN_PROFILE or NOTARY_KEY_PATH, NOTARY_KEY_ID, and NOTARY_ISSUER_ID." >&2
    exit 1
fi

xcrun notarytool submit "$UPLOAD_ARCHIVE" \
    "${NOTARY_ARGS[@]}" \
    --wait \
    --output-format json | tee "$NOTARY_RESULT"

if ! jq -e '.status == "Accepted"' "$NOTARY_RESULT" >/dev/null; then
    echo "Apple did not accept the notarization submission. See $NOTARY_RESULT." >&2
    exit 1
fi

xcrun stapler staple -v "$APP_DIR"
xcrun stapler validate -v "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
spctl --assess --type execute --verbose=4 "$APP_DIR"

# Repackage only after stapling so the downloadable archive contains the ticket.
rm -f -- "$FINAL_ARCHIVE" "$CHECKSUM_FILE"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$FINAL_ARCHIVE"
(
    cd "$DIST_DIR"
    shasum -a 256 "$ARCHIVE_BASENAME" > "$ARCHIVE_BASENAME.sha256"
)

echo "$FINAL_ARCHIVE"
echo "$CHECKSUM_FILE"
