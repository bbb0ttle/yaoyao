//! sokol C library build for native, iOS, and wasm targets.

const std = @import("std");
const Build = std.Build;

const sokol_build = @import("sokol");
const ios = @import("ios.zig");

pub fn buildClib(
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
        lib.step.dependOn(sokol_build.emSdkInstallStep(b, dep_emsdk, .{}));
        mod.addSystemIncludePath(dep_emsdk.path("upstream/emscripten/cache/sysroot/include"));
    } else if (target.result.os.tag == .ios) {
        ios.addSdkPaths(b, target, mod);
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
