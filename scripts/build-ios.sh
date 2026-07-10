#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "==> Building oayao for iOS Simulator (aarch64)..."
zig build -Dtarget=aarch64-ios-simulator

echo "==> Creating Oayao.app bundle..."
zig build ios-app -Dtarget=aarch64-ios-simulator

# Check if a simulator is already booted
BOOTED=$(xcrun simctl list devices booted | grep -E 'iPhone|iPad' | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')

if [ -z "$BOOTED" ]; then
    echo "==> No booted simulator found. Booting iPhone 17..."
    DEVICE_ID=$(xcrun simctl list devices available | grep -m1 "iPhone 17 (" | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
    if [ -z "$DEVICE_ID" ]; then
        echo "Error: No available iPhone simulator found."
        exit 1
    fi
    xcrun simctl boot "$DEVICE_ID"
    echo "==> Waiting for simulator to boot..."
    until xcrun simctl list devices booted | grep -q "$DEVICE_ID"; do sleep 1; done
else
    DEVICE_ID="$BOOTED"
    echo "==> Using already booted simulator: $DEVICE_ID"
fi

echo "==> Installing Oayao.app to simulator..."
xcrun simctl install "$DEVICE_ID" zig-out/Oayao.app

echo "==> Launching oayao in simulator..."
xcrun simctl launch "$DEVICE_ID" com.bkking.oayao

echo "==> Bringing Simulator app to foreground..."
open -a Simulator

echo "==> Done. oayao is running in the iOS Simulator."
