const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

const sokol_build = @import("sokol");

pub fn build(b: *Build) !void {
    var target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });
    const is_web = target.result.cpu.arch.isWasm();

    // Override iOS deployment target: min 12.0, SDK 26.5 (required by App Store Connect).
    // Must re-resolve the query so the version range is correctly embedded in the binary.
    if (target.result.os.tag == .ios) {
        var query = target.query;
        query.os_version_min = .{ .semver = .{ .major = 15, .minor = 0, .patch = 0 } };
        query.os_version_max = .{ .semver = .{ .major = 26, .minor = 5, .patch = 0 } };
        target = b.resolveTargetQuery(query);
    }

    const dep_sokol = b.dependency("sokol", .{});
    const dep_emsdk = b.dependency("emsdk", .{});

    // Create our own sokol module (not dep_sokol.module("sokol")) to avoid
    // the pre-linked sokol_clib which has macOS frameworks baked in.
    const mod_sokol = b.createModule(.{
        .root_source_file = dep_sokol.path("src/sokol/sokol.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- Build sokol C library with correct paths ---
    const lib_sokol = try buildSokolLib(b, dep_sokol, dep_emsdk, target, optimize, is_web);
    mod_sokol.linkLibrary(lib_sokol);

    // --- Shader compilation ---
    const shd_step = try sokol_build.shdc.createSourceFile(b, .{
        .shdc_dep = b.dependency("shdc", .{}),
        .input = "src/shaders/particle.glsl",
        .output = "src/shaders/particle.glsl.zig",
        .slang = .{
            .glsl300es = true,
            .metal_macos = true,
            .metal_ios = true,
        },
        .reflection = true,
    });

    // --- App module ---
    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = mod_sokol },
        },
    });

    // Add iOS SDK paths to the app module (needed for framework resolution at link time)
    if (target.result.os.tag == .ios) {
        const sdk_root = iosSdkRoot(b, target);
        const sdk_usr = b.fmt("{s}/usr", .{sdk_root});
        const sdk_fw = b.fmt("{s}/System/Library/Frameworks", .{sdk_root});
        const sdk_subfw = b.fmt("{s}/System/Library/SubFrameworks", .{sdk_root});
        app_mod.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{sdk_usr}) });
        app_mod.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{sdk_usr}) });
        app_mod.addSystemFrameworkPath(.{ .cwd_relative = sdk_fw });
        app_mod.addSystemFrameworkPath(.{ .cwd_relative = sdk_subfw });
    }

    if (!is_web) {
        if (target.result.os.tag == .ios) {
            // Build static library; Apple's ld64 links the final binary in createIosAppBundle.
            // This avoids Zig's LLD which lacks LC_ENCRYPTION_INFO, correct segment alignment,
            // and proper SDK version embedding required by App Store Connect.
            const lib = b.addLibrary(.{
                .name = "oayao",
                .root_module = app_mod,
            });
            lib.step.dependOn(shd_step);
            const install = b.addInstallArtifact(lib, .{});
            b.getInstallStep().dependOn(&install.step);

            const app_step = try createIosAppBundle(b, lib, lib_sokol, target);
            const install_app = b.step("ios-app", "Build Oayao.app bundle for iOS");
            install_app.dependOn(app_step);
        } else {
            const exe = b.addExecutable(.{
                .name = "oayao",
                .root_module = app_mod,
            });
            exe.step.dependOn(shd_step);
            const install = b.addInstallArtifact(exe, .{});
            b.getInstallStep().dependOn(&install.step);

            const run_cmd = b.addRunArtifact(exe);
            run_cmd.step.dependOn(&install.step);
            const run_step = b.step("run", "Run oayao on desktop");
            run_step.dependOn(&run_cmd.step);
        }
    } else {
        const lib = b.addLibrary(.{
            .name = "oayao",
            .root_module = app_mod,
        });
        lib.step.dependOn(shd_step);

        const link_step = try sokol_build.emLinkStep(b, .{
            .lib_main = lib,
            .target = target,
            .optimize = optimize,
            .emsdk = b.dependency("emsdk", .{}),
            .use_webgl2 = true,
            .use_emmalloc = true,
            .use_filesystem = false,
            .shell_file_path = b.path("web/shell.html"),
            .extra_args = &.{ "-sSTACK_SIZE=512KB", "-sENVIRONMENT=web", "-sERROR_ON_UNDEFINED_SYMBOLS=0", "-sEXPORTED_FUNCTIONS=['_main','_trigger_meteor_shower']" },
        });

        const web_step = b.step("web", "Build oayao for web");
        web_step.dependOn(&link_step.step);

        const emrun = sokol_build.emRunStep(b, .{ .name = "oayao", .emsdk = b.dependency("emsdk", .{}) });
        emrun.step.dependOn(&link_step.step);
        const run_web = b.step("run-web", "Run oayao in browser");
        run_web.dependOn(&emrun.step);
    }

    // --- Tests ---
    const test_step = b.step("test", "Run unit tests");

    const tests_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = tests_mod });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
}

fn buildSokolLib(
    b: *Build,
    dep_sokol: *Build.Dependency,
    dep_emsdk: *Build.Dependency,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    is_web: bool,
) !*Build.Step.Compile {
    const mod = b.addModule("mod_sokol_clib", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const lib = b.addLibrary(.{
        .name = "sokol_clib",
        .linkage = .static,
        .root_module = mod,
    });

    const csources = [_][]const u8{
        "sokol_log.c",   "sokol_app.c",   "sokol_gfx.c",       "sokol_time.c",
        "sokol_audio.c", "sokol_gl.c",    "sokol_debugtext.c", "sokol_shape.c",
        "sokol_glue.c",  "sokol_fetch.c",
    };

    const cflags_native_debug = [_][]const u8{ "-DIMPL", "-DSOKOL_METAL", "-ObjC", "-DSOKOL_DEBUG", "-fno-sanitize=undefined" };
    const cflags_native_release = [_][]const u8{ "-DIMPL", "-DNDEBUG", "-DSOKOL_METAL", "-ObjC", "-fno-sanitize=undefined" };
    const cflags_web_debug = [_][]const u8{ "-DIMPL", "-DSOKOL_GLES3", "-fno-sanitize=undefined" };
    const cflags_web_release = [_][]const u8{ "-DIMPL", "-DNDEBUG", "-DSOKOL_GLES3", "-fno-sanitize=undefined" };

    const cflags: []const []const u8 = if (is_web)
        (if (optimize != .Debug) &cflags_web_release else &cflags_web_debug)
    else
        (if (optimize != .Debug) &cflags_native_release else &cflags_native_debug);

    if (is_web) {
        const emsdk_install_step = emSdkEnsureStep(b, dep_emsdk);
        lib.step.dependOn(emsdk_install_step);
        mod.addSystemIncludePath(dep_emsdk.path("upstream/emscripten/cache/sysroot/include"));
    } else if (target.result.os.tag == .ios) {
        const sdk_root = iosSdkRoot(b, target);
        const sdk_usr = b.fmt("{s}/usr", .{sdk_root});
        const sdk_fw = b.fmt("{s}/System/Library/Frameworks", .{sdk_root});
        const sdk_subfw = b.fmt("{s}/System/Library/SubFrameworks", .{sdk_root});
        mod.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{sdk_usr}) });
        mod.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{sdk_usr}) });
        mod.addSystemFrameworkPath(.{ .cwd_relative = sdk_fw });
        mod.addSystemFrameworkPath(.{ .cwd_relative = sdk_subfw });
        mod.linkFramework("QuartzCore", .{});
        mod.linkFramework("AudioToolbox", .{});
        mod.linkFramework("Metal", .{});
        mod.linkFramework("Foundation", .{});
        mod.linkFramework("UIKit", .{});
        mod.linkFramework("AVFoundation", .{});
        mod.linkFramework("CoreGraphics", .{});
    } else {
        mod.linkFramework("QuartzCore", .{});
        mod.linkFramework("AudioToolbox", .{});
        mod.linkFramework("Metal", .{});
        mod.linkFramework("AppKit", .{});
    }

    inline for (csources) |csrc| {
        mod.addCSourceFile(.{
            .file = dep_sokol.path("src/sokol/c/" ++ csrc),
            .flags = cflags,
        });
    }

    b.installArtifact(lib);
    return lib;
}

fn emSdkEnsureStep(b: *Build, emsdk: *Build.Dependency) *Build.Step {
    return sokol_build.emSdkInstallStep(b, emsdk, .{});
}

fn xcodeDeveloperDir(b: *Build) []const u8 {
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

fn iosSdkRoot(b: *Build, target: Build.ResolvedTarget) []const u8 {
    const developer = xcodeDeveloperDir(b);
    if (target.result.abi == .simulator) {
        return b.fmt("{s}/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk", .{developer});
    } else {
        return b.fmt("{s}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk", .{developer});
    }
}

fn createIosAppBundle(
    b: *Build,
    lib: *Build.Step.Compile,
    lib_sokol: *Build.Step.Compile,
    target: Build.ResolvedTarget,
) !*Build.Step {
    const platform = if (target.result.abi == .simulator) "iphonesimulator" else "iphoneos";
    const sdk_root = iosSdkRoot(b, target);
    const developer_dir = xcodeDeveloperDir(b);

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
        \\echo "Created Oayao.app bundle at zig-out/Oayao.app"
    , .{ sdk_root, swift_target, platform, clang_target, developer_dir, platform });

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
