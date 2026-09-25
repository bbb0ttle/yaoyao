#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "==> Building oayao for Web (wasm32-emscripten)..."
zig build -Dtarget=wasm32-emscripten -Drelease=true

echo "==> Starting web dev server..."
echo "    (emrun will open your browser automatically)"
zig build run-web -Dtarget=wasm32-emscripten -Drelease=true
