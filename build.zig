const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const optimize = b.standardOptimizeOption(.{});

    const wasm_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "z-canvas",
        .root_module = wasm_module,
    });
    exe.entry = .disabled;
    exe.rdynamic = true;

    const wasm_build = b.step("wasm", "Build wasm and copy to public/");
    wasm_build.dependOn(&exe.step);

    const install_wasm = b.addInstallFile(exe.getEmittedBin(), "public/z-canvas.wasm");
    wasm_build.dependOn(&install_wasm.step);

    const native_target = b.standardTargetOptions(.{});
    const test_step = b.step("test", "Run tests");

    const test_modules = [_][]const u8{
        "src/types.zig",
        "src/math.zig",
        "src/font.zig",
        "src/fmt.zig",
    };

    for (test_modules) |path| {
        const mod = b.addModule(path, .{
            .root_source_file = b.path(path),
            .target = native_target,
        });
        const module_tests = b.addTest(.{ .root_module = mod });
        const run_tests = b.addRunArtifact(module_tests);
        test_step.dependOn(&run_tests.step);
    }
}
