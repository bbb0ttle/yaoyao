const std = @import("std");

pub fn build(b: *std.Build) void {
    // ---------- Web build (wasm32-freestanding) ----------
    const wasm_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = .ReleaseFast,
    });

    const exe = b.addExecutable(.{
        .name = "z-canvas",
        .root_module = wasm_module,
    });
    exe.entry = .disabled;
    exe.rdynamic = true;

    const wasm_build = b.step("wasm", "Build wasm and copy to public/");
    wasm_build.dependOn(&exe.step);

    const copy = b.addSystemCommand(&.{ "cp" });
    copy.addArtifactArg(exe);
    copy.addArg("public/");
    copy.step.dependOn(&exe.step);
    wasm_build.dependOn(&copy.step);

    // ---------- iOS build (static library + XCFramework) ----------
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });
    const ios_build = b.step("ios", "Build iOS XCFramework");

    const device_lib = createIOSLib(b, .aarch64, .none, optimize);
    const sim_arm_lib = createIOSLib(b, .aarch64, .simulator, optimize);
    const sim_x86_lib = createIOSLib(b, .x86_64, .simulator, optimize);

    // Combine simulator slices into a single fat static library.
    const sim_fat = b.addSystemCommand(&.{ "lipo", "-create", "-output" });
    const sim_fat_out = sim_fat.addOutputFileArg("libzcanvas.a");
    sim_fat.addArtifactArg(sim_arm_lib);
    sim_fat.addArtifactArg(sim_x86_lib);

    // Package device and simulator libraries into an XCFramework.
    const rm = b.addSystemCommand(&.{ "rm", "-rf" });
    rm.addDirectoryArg(b.path("ios/ZCanvas.xcframework"));

    const xcframework = b.addSystemCommand(&.{ "xcodebuild", "-create-xcframework" });
    xcframework.addArg("-library");
    xcframework.addArtifactArg(device_lib);
    xcframework.addArg("-headers");
    xcframework.addDirectoryArg(b.path("ios/include"));
    xcframework.addArg("-library");
    xcframework.addFileArg(sim_fat_out);
    xcframework.addArg("-headers");
    xcframework.addDirectoryArg(b.path("ios/include"));
    xcframework.addArg("-output");
    xcframework.addDirectoryArg(b.path("ios/ZCanvas.xcframework"));
    xcframework.step.dependOn(&rm.step);

    ios_build.dependOn(&xcframework.step);
}

fn createIOSLib(
    b: *std.Build,
    arch: std.Target.Cpu.Arch,
    abi: std.Target.Abi,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = arch,
            .os_tag = .ios,
            .abi = abi,
        }),
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zcanvas",
        .root_module = module,
    });
    lib.entry = .disabled;
    return lib;
}
