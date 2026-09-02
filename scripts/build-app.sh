#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/Thermal Cam.app"
CONTENTS_DIR="$APP_DIR/Contents"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

if ! [[ "$APP_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' ]]; then
    echo "APP_VERSION must be a semantic version such as 0.1.0." >&2
    exit 1
fi

if ! [[ "$BUILD_NUMBER" =~ '^[0-9]+$' ]]; then
    echo "BUILD_NUMBER must contain only digits." >&2
    exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required to locate libusb. Install Homebrew and run: brew install libusb" >&2
    exit 1
fi

LIBUSB_PREFIX="$(brew --prefix libusb 2>/dev/null || true)"
if [[ -z "$LIBUSB_PREFIX" || ! -d "$LIBUSB_PREFIX" ]]; then
    echo "libusb is required. Install it with: brew install libusb" >&2
    exit 1
fi

cd "$PROJECT_DIR"
swift build -c release

BINARY="$PROJECT_DIR/.build/release/ThermalCam"
if [[ ! -x "$BINARY" ]]; then
    echo "Swift build did not produce $BINARY" >&2
    exit 1
fi

# This path is intentionally narrow: only this project's generated app bundle.
if [[ -e "$APP_DIR" ]]; then
    rm -rf -- "$APP_DIR"
fi
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Frameworks" "$CONTENTS_DIR/Resources"

cp "$BINARY" "$CONTENTS_DIR/MacOS/ThermalCam"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

ICON_SOURCE="$PROJECT_DIR/Resources/IconLayers/AppIcon.icon"
if [[ ! -d "$ICON_SOURCE" ]]; then
    echo "Missing Icon Composer source: $ICON_SOURCE" >&2
    exit 1
fi

ICON_WORK="$(mktemp -d "${TMPDIR:-/tmp}/thermal-cam-icon.XXXXXX")"
ICON_OUTPUT="$ICON_WORK/CompiledIcon"
ICON_PARTIAL_PLIST="$ICON_WORK/IconInfo.plist"
mkdir -p "$ICON_OUTPUT"
trap 'rm -rf -- "$ICON_WORK"' EXIT

if ! xcrun actool \
    --compile "$ICON_OUTPUT" \
    --platform macosx \
    --minimum-deployment-target 15.0 \
    --target-device mac \
    --app-icon AppIcon \
    --output-partial-info-plist "$ICON_PARTIAL_PLIST" \
    --output-format human-readable-text \
    "$ICON_SOURCE"; then
    echo "Could not compile the layered icon. Xcode 26.4 or later is required." >&2
    exit 1
fi

cp "$ICON_OUTPUT/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
cp "$ICON_OUTPUT/Assets.car" "$CONTENTS_DIR/Resources/Assets.car"

LINKED_LIBUSB="$(otool -L "$CONTENTS_DIR/MacOS/ThermalCam" | awk '/libusb-1\.0.*dylib/ { print $1 }')"
if [[ -z "$LINKED_LIBUSB" || ! -f "$LINKED_LIBUSB" ]]; then
    echo "Could not find the libusb library linked by the app." >&2
    exit 1
fi

LIBUSB_NAME="${LINKED_LIBUSB:t}"
cp "$LINKED_LIBUSB" "$CONTENTS_DIR/Frameworks/$LIBUSB_NAME"
install_name_tool -id "@executable_path/../Frameworks/$LIBUSB_NAME" "$CONTENTS_DIR/Frameworks/$LIBUSB_NAME"
install_name_tool -change "$LINKED_LIBUSB" "@executable_path/../Frameworks/$LIBUSB_NAME" "$CONTENTS_DIR/MacOS/ThermalCam"

SIGNING_ARGS=(--force --sign "$CODE_SIGN_IDENTITY")
if [[ "$CODE_SIGN_IDENTITY" != "-" ]]; then
    SIGNING_ARGS+=(--options runtime --timestamp)
fi

# Sign nested code first, then seal the app. Avoid --deep for signing because it
# can hide incorrectly signed nested code in release builds.
codesign "${SIGNING_ARGS[@]}" "$CONTENTS_DIR/Frameworks/$LIBUSB_NAME" >/dev/null
codesign "${SIGNING_ARGS[@]}" "$APP_DIR" >/dev/null
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
