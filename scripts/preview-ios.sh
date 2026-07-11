#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# --- Argument parsing ---
DEVICE="${PREVIEW_DEVICE:-iPhone 17}"
NO_BUILD=false

usage() {
    echo "Usage: $0 [--device <name>] [--no-build]"
    echo "  --device <name>  Target simulator device (default: iPhone 17)"
    echo "                    Override with PREVIEW_DEVICE env var"
    echo "  --no-build       Skip zig build steps, reuse existing zig-out/Oayao.app"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device)
            DEVICE="$2"
            shift 2
            ;;
        --no-build)
            NO_BUILD=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo "==> Preview target device: $DEVICE"

# --- Build ---
if [ "$NO_BUILD" = false ]; then
    echo "==> Building oayao for iOS Simulator (aarch64)..."
    zig build -Dtarget=aarch64-ios-simulator

    echo "==> Creating Oayao.app bundle..."
    zig build ios-app -Dtarget=aarch64-ios-simulator
else
    if [ ! -d "zig-out/Oayao.app" ]; then
        echo "Error: --no-build specified but zig-out/Oayao.app does not exist."
        echo "Run without --no-build first to create the app bundle."
        exit 1
    fi
    echo "==> Skipping build (--no-build), using existing zig-out/Oayao.app"
fi

# --- Find or boot simulator ---
find_simulator() {
    local pattern="$1"
    local state="$2"
    xcrun simctl list devices "$state" | grep -i "$pattern" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/'
}

# Prefer an already-booted device matching the requested name.
BOOTED=$(find_simulator "$DEVICE" "booted")

if [ -n "$BOOTED" ]; then
    DEVICE_ID="$BOOTED"
    echo "==> Using already booted simulator: $DEVICE_ID"
else
    echo "==> No booted '$DEVICE' found. Looking for available device..."
    DEVICE_ID=$(find_simulator "$DEVICE" "available")

    if [ -z "$DEVICE_ID" ]; then
        echo "Error: No available simulator matching '$DEVICE' found."
        echo "Available devices:"
        xcrun simctl list devices available | grep -E 'iPhone|iPad' | head -10
        exit 1
    fi

    echo "==> Booting $DEVICE ($DEVICE_ID)..."
    xcrun simctl boot "$DEVICE_ID"

    echo "==> Waiting for simulator to boot..."
    # xcrun simctl bootstatus was introduced in Xcode 15 (2023).
    # Fall back to polling if unavailable.
    if xcrun simctl bootstatus "$DEVICE_ID" -b 2>/dev/null; then
        :
    else
        until xcrun simctl list devices booted | grep -q "$DEVICE_ID"; do
            sleep 1
        done
        # Give it an extra moment to finish boot animations.
        sleep 2
    fi
fi

# --- Install ---
echo "==> Installing Oayao.app to simulator..."
xcrun simctl install "$DEVICE_ID" zig-out/Oayao.app

# --- Launch ---
echo "==> Launching oayao in simulator..."
xcrun simctl launch "$DEVICE_ID" com.bbking.oayao

# --- Bring to foreground ---
echo "==> Bringing Simulator app to foreground..."
open -a Simulator

echo "==> Done. oayao is running in the iOS Simulator."
