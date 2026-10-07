#!/bin/zsh
# Builds Notch in Release and packages it as a disk image (Notch-<version>.dmg) with an Applications
# shortcut, ready to attach to a GitHub release. Uses only Apple's tools.
#
# Usage (from anywhere):  Tools/make-dmg.sh
#
# Signing: builds are signed with the identity set in the project. For other Macs to open the app
# without a warning, it must be signed with a "Developer ID Application" certificate and notarized,
# which needs a paid Apple Developer Program membership. When such a certificate is in the keychain
# and a notarytool profile is named in NOTARY_PROFILE (xcrun notarytool store-credentials), this
# script signs with it, notarizes the image and staples the ticket. Otherwise it says so and makes an
# unnotarized image, which people can still open via System Settings → Privacy & Security → Open Anyway.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build.noindex"   # ".noindex": Spotlight skips it, so it never offers this copy instead of the installed app
DIST_DIR="$ROOT/dist"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD)"

DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"

echo "→ Building Release (build $BUILD_NUMBER)…"
SIGNING_ARGS=()
if [[ -n "$DEVELOPER_ID" ]]; then
    echo "→ Signing with $DEVELOPER_ID, hardened runtime on"
    SIGNING_ARGS=(CODE_SIGN_IDENTITY="$DEVELOPER_ID" CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp)
else
    SIGNING_ARGS=(CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO)
fi
xcodebuild build \
    -project "$ROOT/Notch.xcodeproj" \
    -scheme Notch \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    "${SIGNING_ARGS[@]}" \
    -quiet

APP="$BUILD_DIR/Build/Products/Release/Notch.app"
if [[ -n "$DEVELOPER_ID" ]]; then
    codesign --verify --deep --strict "$APP"
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST_DIR/Notch-$VERSION.dmg"

echo "→ Packaging $DMG"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Notch.app"
ln -s /Applications "$STAGING/Applications"
mkdir -p "$DIST_DIR"
rm -f "$DMG"
hdiutil create -volname "Notch $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -quiet "$DMG"

if [[ -n "$DEVELOPER_ID" && -n "${NOTARY_PROFILE:-}" ]]; then
    codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
    echo "→ Notarizing (this takes a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "✓ $DMG — signed, notarized and stapled: opens on any Mac without a warning"
else
    echo "✓ $DMG"
    echo "  Not notarized (needs a Developer ID certificate and NOTARY_PROFILE). On other Macs, people"
    echo "  open it once via System Settings → Privacy & Security → Open Anyway."
fi
