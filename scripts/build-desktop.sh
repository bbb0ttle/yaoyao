#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "==> Building oayao for macOS desktop..."
zig build -Drelease=true

echo "==> Running oayao..."
zig build run -Drelease=true
