#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Use release Xcode for App Store submissions (beta Xcode builds are rejected).
# Set DEVELOPER_DIR before building, or export it in .env.
# Example: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
if [ -z "$DEVELOPER_DIR" ]; then
    DEFAULT_XCODE="/Applications/Xcode.app/Contents/Developer"
    if [ -d "$DEFAULT_XCODE" ]; then
        export DEVELOPER_DIR="$DEFAULT_XCODE"
        echo "==> Using Xcode at $DEVELOPER_DIR"
        echo "    (set DEVELOPER_DIR in .env to override)"
    fi
fi

# Load .env file if present
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

# ============================================================
# Configuration — set these via .env or environment variables
# ============================================================
# Required:
#   APP_STORE_KEY_ID     — App Store Connect API Key ID
#   APP_STORE_ISSUER_ID  — App Store Connect Issuer ID (UUID)
# Optional:
#   API_PRIVATE_KEYS_DIR — Directory containing AuthKey_<KEY_ID>.p8
#                           (defaults to ~/.private_keys)
#   SIGNING_IDENTITY     — codesign identity name (defaults to "Apple Distribution")
#   PROVISIONING_PROFILE — path to .mobileprovision file
#                           (defaults to ~/Library/MobileDevice/Provisioning Profiles/yconnect.mobileprovision)

if [ -z "$APP_STORE_KEY_ID" ] || [ -z "$APP_STORE_ISSUER_ID" ]; then
    echo "Error: App Store Connect API credentials not set."
    echo ""
    echo "Before using this script:"
    echo "  1. Go to App Store Connect > Users and Access > Integrations > Keys"
    echo "  2. Create an API key with 'Developer' role"
    echo "  3. Download the .p8 file to ~/.private_keys/AuthKey_XXXXXXXXXX.p8"
    echo ""
    echo "Then set environment variables:"
    echo "  export APP_STORE_KEY_ID=XXXXXXXXXX"
    echo "  export APP_STORE_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    exit 1
fi

SIGNING_IDENTITY="${SIGNING_IDENTITY:-Apple Distribution}"
PROVISIONING_PROFILE="${PROVISIONING_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/yconnect.mobileprovision}"
ENTITLEMENTS="$PROJECT_DIR/ios/Oayao.entitlements"

# ============================================================
# Version & Build Number
# ============================================================
# APP_VERSION          — marketing version (e.g., "1.2.0"). Defaults to
#                        CFBundleShortVersionString in Info.plist.
# APP_BUILD_NUMBER     — integer build number. Defaults to auto-increment
#                        via git commit count.

# Default: read current version from Info.plist (before build overwrites it).
CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_DIR/ios/Info.plist" 2>/dev/null || echo "1.1.0")"
APP_VERSION="${APP_VERSION:-$CURRENT_VERSION}"

if [ -z "$APP_BUILD_NUMBER" ]; then
    APP_BUILD_NUMBER="$(git -C "$PROJECT_DIR" rev-list --count HEAD 2>/dev/null || echo "1")"
    echo "==> Auto-incremented build number: $APP_BUILD_NUMBER"
fi
echo "==> Version: $APP_VERSION ($APP_BUILD_NUMBER)"

# ============================================================
# Xcode / SDK validation
# ============================================================

XCODE_VERSION_FULL="$(xcrun xcodebuild -version 2>/dev/null)"
XCODE_VERSION="$(echo "$XCODE_VERSION_FULL" | head -1 | awk '{print $2}')"
XCODE_BUILD="$(echo "$XCODE_VERSION_FULL" | tail -1 | awk '{print $3}')"
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo "0")"
SDK_BUILD="$(xcrun --sdk iphoneos --show-sdk-build-version 2>/dev/null || echo "0")"

echo "==> Xcode $XCODE_VERSION ($XCODE_BUILD), SDK $SDK_VERSION ($SDK_BUILD)"

# Beta Xcode builds carry a trailing lowercase seed letter in the build number
# (e.g. 17A5295e); the version string itself never contains the word "beta".
if echo "$XCODE_VERSION_FULL" | grep -qi 'beta\|preview\|seed' || \
   echo "$XCODE_BUILD" | grep -qE '^[0-9]+[A-Z]+[0-9]+[a-z]+$'; then
    echo ""
    echo "ERROR: You are using a beta/preview version of Xcode ($XCODE_VERSION $XCODE_BUILD)."
    echo "App Store Connect requires a release or RC version of Xcode."
    echo ""
    echo "To fix:"
    echo "  1. Install the release Xcode from the Mac App Store or"
    echo "     https://developer.apple.com/download/applications/"
    echo "  2. Set DEVELOPER_DIR in .env to point to the release Xcode"
    exit 1
fi

# Pin the exact GM toolchain App Store Connect expects. A beta toolchain can
# otherwise slip through the checks above and only fail after upload. When
# Apple releases a new GM, update these defaults (or set them in .env) —
# see https://xcodereleases.com for the current GM build numbers.
EXPECTED_XCODE_BUILD="${EXPECTED_XCODE_BUILD:-17F113}"
EXPECTED_SDK_BUILD="${EXPECTED_SDK_BUILD:-23F81a}"

if [ "$XCODE_BUILD" != "$EXPECTED_XCODE_BUILD" ] || [ "$SDK_BUILD" != "$EXPECTED_SDK_BUILD" ]; then
    echo ""
    echo "ERROR: Toolchain does not match the pinned GM builds."
    echo "  Xcode build: $XCODE_BUILD (expected $EXPECTED_XCODE_BUILD)"
    echo "  SDK build:   $SDK_BUILD (expected $EXPECTED_SDK_BUILD)"
    echo ""
    echo "Either install the expected GM Xcode, or — if Apple has shipped a"
    echo "newer GM — update EXPECTED_XCODE_BUILD / EXPECTED_SDK_BUILD in .env."
    exit 1
fi

# ============================================================
# Build
# ============================================================

echo "==> Cleaning previous build artifacts..."
rm -rf "$PROJECT_DIR/zig-out" "$PROJECT_DIR/.zig-cache"

echo "==> Building oayao for iOS Device (aarch64)..."
zig build -Dtarget=aarch64-ios -Drelease=true

echo "==> Creating Oayao.app bundle..."
zig build ios-app -Dtarget=aarch64-ios -Drelease=true

if [ ! -d "zig-out/Oayao.app" ]; then
    echo "Error: Oayao.app bundle was not created."
    exit 1
fi

# Verify the toolchain metadata actool stamped into the product — this is what
# App Store Connect inspects, and it must match the GM toolchain above.
STAMPED_XCODE_BUILD="$(/usr/libexec/PlistBuddy -c "Print :DTXcodeBuild" zig-out/Oayao.app/Info.plist 2>/dev/null || echo missing)"
STAMPED_SDK_BUILD="$(/usr/libexec/PlistBuddy -c "Print :DTSDKBuild" zig-out/Oayao.app/Info.plist 2>/dev/null || echo missing)"
echo "==> Stamped metadata: DTXcodeBuild=$STAMPED_XCODE_BUILD, DTSDKBuild=$STAMPED_SDK_BUILD"
if [ "$STAMPED_XCODE_BUILD" != "$XCODE_BUILD" ] || [ "$STAMPED_SDK_BUILD" != "$SDK_BUILD" ]; then
    echo ""
    echo "ERROR: Built app metadata does not match the selected GM toolchain."
    echo "Refusing to upload — the binary would be rejected as a beta build."
    exit 1
fi

# ============================================================
# Stamp version into the built .app
# ============================================================

echo "==> Stamping version $APP_VERSION ($APP_BUILD_NUMBER) into Info.plist..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" zig-out/Oayao.app/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD_NUMBER" zig-out/Oayao.app/Info.plist

# ============================================================
# Code Signing
# ============================================================

echo "==> Signing Oayao.app with identity: $SIGNING_IDENTITY..."

if [ ! -f "$PROVISIONING_PROFILE" ]; then
    echo "Error: Provisioning profile not found at $PROVISIONING_PROFILE"
    exit 1
fi

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "Error: Entitlements file not found at $ENTITLEMENTS"
    exit 1
fi

cp "$PROVISIONING_PROFILE" zig-out/Oayao.app/embedded.mobileprovision

codesign --force --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp=none \
    zig-out/Oayao.app

# codesign on Xcode 26+ puts CodeResources in _CodeSignature/;
# App Store Connect still expects a root-level symlink in some cases
if [ ! -e "zig-out/Oayao.app/CodeResources" ]; then
    ln -sf _CodeSignature/CodeResources zig-out/Oayao.app/CodeResources
fi

echo "    Signed successfully."

# ============================================================
# Package IPA
# ============================================================

echo "==> Packaging IPA..."
rm -rf zig-out/Oayao.ipa /tmp/oayao-payload
mkdir -p /tmp/oayao-payload/Payload
ditto zig-out/Oayao.app /tmp/oayao-payload/Payload/Oayao.app
ditto -c -k --keepParent /tmp/oayao-payload/Payload "$PROJECT_DIR/zig-out/Oayao.ipa"
rm -rf /tmp/oayao-payload
echo "    Created zig-out/Oayao.ipa"

# ============================================================
# Validate
# ============================================================

echo "==> Validating IPA with App Store Connect..."
xcrun altool --validate-app -f zig-out/Oayao.ipa \
    --api-key "$APP_STORE_KEY_ID" \
    --api-issuer "$APP_STORE_ISSUER_ID" \
    --type ios

# ============================================================
# Upload to TestFlight
# ============================================================

echo "==> Uploading to TestFlight..."
xcrun altool --upload-package zig-out/Oayao.ipa \
    --api-key "$APP_STORE_KEY_ID" \
    --api-issuer "$APP_STORE_ISSUER_ID" \
    --wait

echo ""
echo "==> Done. Check TestFlight at:"
echo "    https://appstoreconnect.apple.com/apps/com.bbking.oayao/testflight"
