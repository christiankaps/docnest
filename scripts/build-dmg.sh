#!/bin/bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────
APP_NAME="DocNest"
SCHEME="DocNest"
PROJECT="DocNest.xcodeproj"
CONFIGURATION="Release"
RELEASE_VERSION="${RELEASE_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/dmg"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_OUTPUT="$BUILD_DIR/$APP_NAME.dmg"

# ─── Helpers ─────────────────────────────────────────────────────
bold() { printf "\033[1m%s\033[0m\n" "$1"; }
step() { printf "\n\033[1;36m==> %s\033[0m\n" "$1"; }
fail() { printf "\033[1;31mError: %s\033[0m\n" "$1" >&2; exit 1; }

# ─── Preflight ───────────────────────────────────────────────────
command -v xcodebuild >/dev/null || fail "xcodebuild not found"
command -v create-dmg >/dev/null || fail "create-dmg not found (install with: brew install create-dmg)"
command -v hdiutil >/dev/null || fail "hdiutil not found"

# ─── Clean previous build ───────────────────────────────────────
step "Cleaning previous build artifacts"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ─── Archive ─────────────────────────────────────────────────────
step "Archiving $APP_NAME ($CONFIGURATION)"
XCODEBUILD_ARGS=(
    -project "$PROJECT_DIR/$PROJECT"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -archivePath "$ARCHIVE_PATH"
    archive
    SKIP_INSTALL=NO
    BUILD_LIBRARY_FOR_DISTRIBUTION=NO
)

if [ -n "$RELEASE_VERSION" ]; then
    XCODEBUILD_ARGS+=(
        "MARKETING_VERSION=$RELEASE_VERSION"
        "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
    )
fi

xcodebuild "${XCODEBUILD_ARGS[@]}" | tail -3

# Verify the archive produced an app
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
[ -d "$APP_PATH" ] || fail "Archive did not produce $APP_NAME.app"

bold "Archived: $APP_PATH"

# ─── Extract version for DMG filename ────────────────────────────
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1")
DMG_NAME="${APP_NAME}_${VERSION}_${BUILD}.dmg"
DMG_OUTPUT="$BUILD_DIR/$DMG_NAME"

bold "Version: $VERSION ($BUILD)"

# ─── Stage the app ───────────────────────────────────────────────
step "Staging app for DMG"
STAGING_DIR="$BUILD_DIR/staging"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

# ─── Create DMG ──────────────────────────────────────────────────
step "Creating DMG"
create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "$APP_NAME.app" 180 170 \
    --app-drop-link 480 170 \
    --hide-extension "$APP_NAME.app" \
    --no-internet-enable \
    "$DMG_OUTPUT" \
    "$STAGING_DIR"

# ─── Verify ──────────────────────────────────────────────────────
if [ -s "$DMG_OUTPUT" ]; then
    hdiutil imageinfo "$DMG_OUTPUT" >/dev/null || fail "DMG failed validation"
    DMG_SIZE=$(du -h "$DMG_OUTPUT" | cut -f1)
    step "Done"
    bold "DMG: $DMG_OUTPUT ($DMG_SIZE)"
    bold "Volume: $APP_NAME"
    bold "Version: $VERSION ($BUILD)"
else
    fail "DMG was not created"
fi
