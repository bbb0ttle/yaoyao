//! iOS target support: SDK resolution and .app bundle creation.

const std = @import("std");
const Build = std.Build;

pub fn xcodeDeveloperDir(b: *Build) []const u8 {
    // Respect DEVELOPER_DIR env var (standard macOS convention) first,
    // then fall back to xcode-select, then hardcoded default.
    if (b.graph.environ_map.get("DEVELOPER_DIR")) |dir| {
        return dir;
    }

    var exit_code: u8 = undefined;
    const result = b.runAllowFail(
        &.{ "xcode-select", "-p" },
        &exit_code,
        .ignore,
    ) catch return "/Applications/Xcode.app/Contents/Developer";
    return std.mem.trimEnd(u8, result, "\n");
}

pub fn sdkRoot(b: *Build, target: Build.ResolvedTarget) []const u8 {
    const developer = xcodeDeveloperDir(b);
    if (target.result.abi == .simulator) {
        return b.fmt("{s}/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk", .{developer});
    } else {
        return b.fmt("{s}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk", .{developer});
    }
}

/// System include/library/framework paths for the iOS SDK, shared by the
/// app module and the sokol C library.
pub fn addSdkPaths(b: *Build, target: Build.ResolvedTarget, mod: *Build.Module) void {
    const sdk_root = sdkRoot(b, target);
    const sdk_usr = b.fmt("{s}/usr", .{sdk_root});
    const sdk_fw = b.fmt("{s}/System/Library/Frameworks", .{sdk_root});
    const sdk_subfw = b.fmt("{s}/System/Library/SubFrameworks", .{sdk_root});
    mod.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{sdk_usr}) });
    mod.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{sdk_usr}) });
    mod.addSystemFrameworkPath(.{ .cwd_relative = sdk_fw });
    mod.addSystemFrameworkPath(.{ .cwd_relative = sdk_subfw });
}

/// Assemble Oayao.app: compile the Swift shell, link with Apple's ld64
/// (Zig's LLD lacks LC_ENCRYPTION_INFO, correct segment alignment, and
/// SDK version embedding required by App Store Connect), copy resources,
/// and stamp toolchain metadata.
pub fn createAppBundle(
    b: *Build,
    lib: *Build.Step.Compile,
    lib_sokol: *Build.Step.Compile,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*Build.Step {
    const platform = if (target.result.abi == .simulator) "iphonesimulator" else "iphoneos";
    const sdk_root = sdkRoot(b, target);
    const developer_dir = xcodeDeveloperDir(b);
    // Plain swiftc does not define DEBUG on its own; pass it so #if DEBUG
    // sections (e.g. the stress-test UI) compile in debug builds only.
    const swift_flags: []const u8 = if (optimize == .Debug) "-Onone -D DEBUG" else "-O";

    // Construct clang target triple from resolved target.
    const clang_arch: []const u8 = if (target.result.cpu.arch == .aarch64) "arm64" else @tagName(target.result.cpu.arch);
    const clang_target = if (target.result.abi == .simulator)
        b.fmt("{s}-apple-ios15.0-simulator", .{clang_arch})
    else
        b.fmt("{s}-apple-ios15.0", .{clang_arch});

    const swift_target = if (target.result.abi == .simulator)
        b.fmt("{s}-apple-ios15.0-simulator", .{clang_arch})
    else
        b.fmt("{s}-apple-ios15.0", .{clang_arch});

    const script = b.fmt(
        \\set -e
        \\ROOT="$(pwd)"
        \\APP="$ROOT/zig-out/Oayao.app"
        \\rm -rf "$APP"
        \\mkdir -p "$APP"
        \\
        \\# Resolve artifact absolute paths before any directory change.
        \\A1="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
        \\A2="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
        \\
        \\# Compile Swift files into object files.
        \\SDK_ROOT="{s}"
        \\SWIFT_DIR="$(mktemp -d /tmp/oayao_swift.XXXXXX)"
        \\trap 'rm -rf "$SWIFT_DIR"' EXIT
        \\cd "$SWIFT_DIR"
        \\swiftc -c \
        \\  {[6]s} \
        \\  -sdk "$SDK_ROOT" \
        \\  -target "{s}" \
        \\  -import-objc-header "$7"/Bridge.h \
        \\  -Xcc -I"$SDK_ROOT/usr/include" \
        \\  "$7"/CallbackBridge.swift \
        \\  "$7"/CalendarManager.swift \
        \\  "$7"/EventDetailSheet.swift \
        \\  "$7"/AddEventSheet.swift \
        \\  "$7"/SettingsStore.swift \
        \\  "$7"/Localization.swift \
        \\  "$7"/SettingsSheet.swift
        \\
        \\# Link with Apple's ld64 via xcrun clang — produces correct LC_ENCRYPTION_INFO,
        \\# segment alignment, SDK version, and PIE that App Store Connect requires.
        \\# Zig's .a archives have misaligned Mach-O members; extract to temp .o files first.
        \\O1="$(mktemp -d /tmp/oayao_o1.XXXXXX)"
        \\O2="$(mktemp -d /tmp/oayao_o2.XXXXXX)"
        \\trap 'rm -rf "$O1" "$O2" "$SWIFT_DIR"' EXIT
        \\ sh -c 'cd "$1" && ar x "$2" 2>/dev/null; chmod 644 ./*.o 2>/dev/null' -- "$O1" "$A1" || true
        \\ sh -c 'cd "$1" && ar x "$2" 2>/dev/null; chmod 644 ./*.o 2>/dev/null' -- "$O2" "$A2" || true
        \\
        \\# Use swiftc for linking — it auto-adds Swift runtime libraries.
        \\xcrun --sdk {s} swiftc -target "{s}" \
        \\  -emit-executable \
        \\  -o "$APP/Oayao" \
        \\  "$O1"/*.o "$O2"/*.o "$SWIFT_DIR"/*.o \
        \\  -Xlinker -framework -Xlinker UIKit \
        \\  -Xlinker -framework -Xlinker Metal \
        \\  -Xlinker -framework -Xlinker QuartzCore \
        \\  -Xlinker -framework -Xlinker Foundation \
        \\  -Xlinker -framework -Xlinker CoreGraphics \
        \\  -Xlinker -framework -Xlinker AudioToolbox \
        \\  -Xlinker -framework -Xlinker AVFoundation \
        \\  -Xlinker -framework -Xlinker EventKit
        \\
        \\cp "$3" "$APP/Info.plist"
        \\cp "$4" "$APP/LaunchScreen.storyboard"
        \\cp "$5" "$APP/PrivacyInfo.xcprivacy"
        \\ACTOOL="{s}/usr/bin/actool"
        \\PLISTBUDDY="/usr/libexec/PlistBuddy"
        \\PARTIAL="/tmp/oayao_partial.plist"
        \\"$ACTOOL" "$6" --compile "$APP" --platform {s} --minimum-deployment-target 15.0 --app-icon AppIcon --output-partial-info-plist "$PARTIAL"
        \\"$PLISTBUDDY" -c "Merge $PARTIAL" "$APP/Info.plist"
        \\rm -f "$PARTIAL"
        \\
        \\# actool only stamps icon keys. App Store Connect inspects the DT*
        \\# toolchain metadata to detect beta builds, so stamp it ourselves
        \\# from the selected toolchain (respects DEVELOPER_DIR).
        \\SDK_VER="$(DEVELOPER_DIR="{[4]s}" /usr/bin/xcrun --sdk {[2]s} --show-sdk-version)"
        \\SDK_BUILD="$(DEVELOPER_DIR="{[4]s}" /usr/bin/xcrun --sdk {[2]s} --show-sdk-build-version)"
        \\XCODE_VER="$(DEVELOPER_DIR="{[4]s}" /usr/bin/xcrun xcodebuild -version | head -1 | cut -d' ' -f2)"
        \\XCODE_BUILD="$(DEVELOPER_DIR="{[4]s}" /usr/bin/xcrun xcodebuild -version | tail -1 | cut -d' ' -f3)"
        \\XCODE_MAJOR="$(echo "$XCODE_VER" | cut -d. -f1)"
        \\XCODE_MINOR="$(echo "$XCODE_VER" | cut -d. -f2)"
        \\XCODE_PATCH="$(echo "$XCODE_VER" | cut -d. -f3)"
        \\[ -z "$XCODE_PATCH" ] && XCODE_PATCH=0
        \\DT_XCODE=$(( XCODE_MAJOR*100 + XCODE_MINOR*10 + XCODE_PATCH ))
        \\"$PLISTBUDDY" \
        \\  -c "Add :DTCompiler string com.apple.compilers.llvm.clang.1_0" \
        \\  -c "Add :DTPlatformName string {[2]s}" \
        \\  -c "Add :DTPlatformVersion string $SDK_VER" \
        \\  -c "Add :DTPlatformBuild string $SDK_BUILD" \
        \\  -c "Add :DTSDKName string {[2]s}$SDK_VER" \
        \\  -c "Add :DTSDKBuild string $SDK_BUILD" \
        \\  -c "Add :DTXcode string $DT_XCODE" \
        \\  -c "Add :DTXcodeBuild string $XCODE_BUILD" \
        \\  "$APP/Info.plist"
        \\echo "Created Oayao.app bundle at zig-out/Oayao.app"
    , .{ sdk_root, swift_target, platform, clang_target, developer_dir, platform, swift_flags });

    const cmd = b.addSystemCommand(&.{ "sh", "-c" });
    cmd.addArg(script);
    cmd.addArg("sh"); // $0
    cmd.addArtifactArg(lib); // $1 — liboayao.a
    cmd.addArtifactArg(lib_sokol); // $2 — libsokol_clib.a
    cmd.addFileArg(b.path("ios/Info.plist")); // $3
    cmd.addFileArg(b.path("ios/Oayao/LaunchScreen.storyboard")); // $4
    cmd.addFileArg(b.path("ios/Oayao/PrivacyInfo.xcprivacy")); // $5
    cmd.addDirectoryArg(b.path("ios/Oayao/Assets.xcassets")); // $6
    cmd.addDirectoryArg(b.path("ios/Oayao")); // $7 — Swift source directory

    return &cmd.step;
}
