const std = @import("std");
const Build = std.Build;

const sokol_build = @import("sokol");
const ios_build = @import("src/build/ios.zig");
const sokol_clib = @import("src/build/sokol.zig");

pub fn build(b: *Build) !void {
    var target = b.standardTargetOptions(.{});
    // Production default is ReleaseSafe: bounds/overflow violations stay
    // panics instead of silent UB. ReleaseFast is opt-in via -Drelease=fast
    // for benchmark-verified builds only.
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });
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
    const lib_sokol = try sokol_clib.buildClib(b, dep_sokol, dep_emsdk, target, optimize, is_web);
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
        ios_build.addSdkPaths(b, target, app_mod);
    }

    if (!is_web) {
        if (target.result.os.tag == .ios) {
            // Build static library; Apple's ld64 links the final binary in the
            // bundle step. This avoids Zig's LLD which lacks LC_ENCRYPTION_INFO,
            // correct segment alignment, and SDK version embedding required by
            // App Store Connect.
            const lib = b.addLibrary(.{
                .name = "oayao",
                .root_module = app_mod,
            });
            lib.step.dependOn(shd_step);
            const install = b.addInstallArtifact(lib, .{});
            b.getInstallStep().dependOn(&install.step);

            const app_step = try ios_build.createAppBundle(b, lib, lib_sokol, target, optimize);
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

        const em_extra_args: []const []const u8 = if (optimize == .Debug)
            &.{ "-sSTACK_SIZE=512KB", "-sENVIRONMENT=web", "-sERROR_ON_UNDEFINED_SYMBOLS=0", "-sEXPORTED_FUNCTIONS=['_main','_trigger_meteor_shower','_oayao_set_days_counter_start_ms']" }
        else
            &.{ "-O3", "-sSTACK_SIZE=512KB", "-sENVIRONMENT=web", "-sERROR_ON_UNDEFINED_SYMBOLS=0", "-sEXPORTED_FUNCTIONS=['_main','_trigger_meteor_shower','_oayao_set_days_counter_start_ms']" };

        const link_step = try sokol_build.emLinkStep(b, .{
            .lib_main = lib,
            .target = target,
            .optimize = optimize,
            .emsdk = b.dependency("emsdk", .{}),
            .use_webgl2 = true,
            .use_emmalloc = true,
            .use_filesystem = false,
            .shell_file_path = b.path("web/shell.html"),
            .extra_args = em_extra_args,
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
    const tests = b.addTest(.{
        .root_module = tests_mod,
        // -Dtest-filter="..." compiles in only matching tests; the full
        // suite is the default.
        .filters = if (b.option([]const u8, "test-filter", "Skip tests whose name lacks the substring")) |filter|
            &.{filter}
        else
            &.{},
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    // --- Format check ---
    const fmt_step = b.step("fmt", "Check formatting with zig fmt");
    const fmt = b.addFmt(.{
        .paths = &.{ b.path("src"), b.path("build.zig"), b.path("build.zig.zon") },
        .check = true,
    });
    fmt_step.dependOn(&fmt.step);
}
