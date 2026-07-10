#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# ============================================================
# Configuration — set these via environment variables
# ============================================================
# Required:
#   APP_STORE_KEY_ID     — App Store Connect API Key ID (e.g. "ABC1234567")
#   APP_STORE_ISSUER_ID  — App Store Connect Issuer ID (UUID)
# Optional:
#   API_PRIVATE_KEYS_DIR — Directory containing AuthKey_<KEY_ID>.p8
#                           (defaults to ~/.private_keys)

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
# Code Signing Check
# ============================================================

if [ ! -d "zig-out/Oayao.app/_CodeSignature" ]; then
    echo ""
    echo "Warning: Oayao.app is not code-signed."
    echo "TestFlight requires a signed app with a valid provisioning profile."
    echo ""
    echo "Sign manually before packaging, for example:"
    echo "  codesign --force --sign \"Apple Distribution\" --entitlements ios/Oayao.entitlements zig-out/Oayao.app"
    echo "  cp ~/path/to/profile.mobileprovision zig-out/Oayao.app/embedded.mobileprovision"
    echo ""
    read -rp "Continue without signing? (y/N) " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        exit 1
    fi
fi

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
echo "    https://appstoreconnect.apple.com/apps/com.bkking.oayao/testflight"
