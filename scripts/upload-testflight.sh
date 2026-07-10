#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# ============================================================
# Configuration — set these via environment variables
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
# Build
# ============================================================

echo "==> Building oayao for iOS Device (aarch64)..."
zig build -Dtarget=aarch64-ios

echo "==> Creating Oayao.app bundle..."
zig build ios-app -Dtarget=aarch64-ios

if [ ! -d "zig-out/Oayao.app" ]; then
    echo "Error: Oayao.app bundle was not created."
    exit 1
fi

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

echo "    Signed successfully."

# ============================================================
# Package IPA
# ============================================================

echo "==> Packaging IPA..."
rm -rf /tmp/oayao-payload zig-out/Oayao.ipa
mkdir -p /tmp/oayao-payload/Payload
cp -R zig-out/Oayao.app /tmp/oayao-payload/Payload/
( cd /tmp/oayao-payload && zip -rq "$PROJECT_DIR/zig-out/Oayao.ipa" Payload )
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
