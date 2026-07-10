# oayao

Particle animation app built with [Zig](https://ziglang.org/) and [sokol](https://github.com/floooh/sokol-zig). Renders a beating heart contour, floating particles, a day counter, and interactive meteor effects on click/touch.

## Prerequisites

- **Zig** 0.14.0 or later ([download](https://ziglang.org/download/))
- **Xcode** (macOS only, required for iOS builds — provides the iOS SDK and Simulator)
- **Emscripten** — downloaded automatically by the build system for web targets

## Quick Start

```bash
# macOS desktop
./scripts/build-desktop.sh

# iOS Simulator
./scripts/build-ios.sh

# Web (browser)
./scripts/build-web.sh

# TestFlight upload
./scripts/upload-testflight.sh
```

## Build & Run

### macOS Desktop

```bash
zig build          # compile
zig build run      # compile and run
# or:
./scripts/build-desktop.sh
```

### iOS Simulator

```bash
zig build -Dtarget=aarch64-ios-simulator        # compile binary
zig build ios-app -Dtarget=aarch64-ios-simulator # create .app bundle
# then install and launch:
xcrun simctl boot "iPhone 17"                              # boot simulator (if needed)
xcrun simctl install booted zig-out/Oayao.app              # install app
xcrun simctl launch booted com.bbking.oayao                # launch app
# or:
./scripts/build-ios.sh
```

For Intel Macs, use `-Dtarget=x86_64-ios-simulator`.

### iOS Device

```bash
zig build -Dtarget=aarch64-ios
zig build ios-app -Dtarget=aarch64-ios
```

The `.app` bundle is created at `zig-out/Oayao.app`. Use Xcode to install it onto a device.

### TestFlight Upload

```bash
# Set credentials
export APP_STORE_KEY_ID=XXXXXXXXXX
export APP_STORE_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# Build, sign, package, validate, and upload
./scripts/upload-testflight.sh
```

The script requires an App Store Connect API key. Place the `.p8` file at `~/.private_keys/AuthKey_<KEY_ID>.p8`. The app must be code-signed with an `Apple Distribution` certificate and include an embedded provisioning profile before upload.

Manual steps:

```bash
zig build -Dtarget=aarch64-ios                    # compile
zig build ios-app -Dtarget=aarch64-ios             # create .app bundle
codesign --force --sign "Apple Distribution" \
  zig-out/Oayao.app                                # sign
cp profile.mobileprovision \
  zig-out/Oayao.app/embedded.mobileprovision        # embed profile
# package and upload:
mkdir -p Payload && cp -R zig-out/Oayao.app Payload/
zip -r Oayao.ipa Payload
xcrun altool --upload-package Oayao.ipa \
  --api-key "$APP_STORE_KEY_ID" \
  --api-issuer "$APP_STORE_ISSUER_ID" \
  --wait
```

### Web (Wasm)

```bash
zig build -Dtarget=wasm32-emscripten   # compile
zig build web                           # link with Emscripten
zig build run-web                       # serve and open in browser
# or:
./scripts/build-web.sh
```

## Project Structure

```
z-canvas/
  build.zig              # Build system (macOS, iOS, Web)
  build.zig.zon          # Dependencies (sokol, sokol-tools-bin, emsdk)
  src/
    main.zig             # Entry point — sokol init/frame/cleanup/event, rendering
    core/
      business.zig       # Rgba, Vec2, heart curve math, 3x5 bitmap font
    Particle.zig         # Particle pool (5000 capacity), free-list allocator
    HeartSystem.zig      # Heart contour, breathing animation, floating particles
    MeteorSystem.zig     # Meteor burst on click/touch
    random.zig           # LCG pseudo-random number generator
    shaders/
      particle.glsl      # Instanced particle shader (GLSL source)
      particle.glsl.zig  # Generated Zig bindings (sokol-shdc output)
  ios/
    Info.plist           # iOS bundle metadata
    Oayao/
      LaunchScreen.storyboard
      PrivacyInfo.xcprivacy
      Assets.xcassets/
  web/
    shell.html           # Emscripten HTML shell
  scripts/
    build-desktop.sh     # One-click: build + run on macOS
    build-ios.sh         # One-click: build + install + launch in iOS Simulator
    build-web.sh         # One-click: build + serve in browser
    upload-testflight.sh # One-click: build + package + upload to TestFlight
```

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Zig |
| Graphics | sokol (Metal on Apple platforms, WebGL2 on web) |
| Shaders | GLSL → compiled via sokol-shdc to Metal / GLSL ES |
| Web | Emscripten + WebGL2 |
| iOS | UIKit + Metal, deployment target 12.0 |
