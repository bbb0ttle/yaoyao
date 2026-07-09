const std = @import("std");

pub fn build(b: *std.Build) void {
    // ---------- Web build (wasm32-freestanding) ----------
    const wasm_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = .ReleaseFast,
    });

    const exe = b.addExecutable(.{
        .name = "oayao",
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

    // Repack each Zig-built archive with Apple's libtool to ensure 64-bit
    // Mach-O members are 8-byte aligned, which Xcode's linker requires.
    const device_a = repackStaticLib(b, device_lib, "liboayao.a");
    const sim_arm_a = repackStaticLib(b, sim_arm_lib, "liboayao.a");
    const sim_x86_a = repackStaticLib(b, sim_x86_lib, "liboayao.a");

    // Combine simulator slices into a single fat static library.
    const sim_fat = b.addSystemCommand(&.{ "lipo", "-create", "-output" });
    const sim_fat_out = sim_fat.addOutputFileArg("liboayao.a");
    sim_fat.addFileArg(sim_arm_a);
    sim_fat.addFileArg(sim_x86_a);

    // Package device and simulator libraries into an XCFramework.
    const rm = b.addSystemCommand(&.{ "rm", "-rf" });
    rm.addDirectoryArg(b.path("ios/Oayao.xcframework"));

    const xcframework = b.addSystemCommand(&.{ "xcodebuild", "-create-xcframework" });
    xcframework.addArg("-library");
    xcframework.addFileArg(device_a);
    xcframework.addArg("-headers");
    xcframework.addDirectoryArg(b.path("ios/include"));
    xcframework.addArg("-library");
    xcframework.addFileArg(sim_fat_out);
    xcframework.addArg("-headers");
    xcframework.addDirectoryArg(b.path("ios/include"));
    xcframework.addArg("-output");
    xcframework.addDirectoryArg(b.path("ios/Oayao.xcframework"));
    xcframework.step.dependOn(&rm.step);

    ios_build.dependOn(&xcframework.step);
}

fn repackStaticLib(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    name: []const u8,
) std.Build.LazyPath {
    const script =
        \\set -e
        \\work_dir="$1_work"
        \\rm -rf "$work_dir"
        \\mkdir -p "$work_dir"
        \\cd "$work_dir"
        \\xcrun ar -x "$OLDPWD/$2"
        \\chmod +r *.o
        \\rm -f __.SYMDEF*
        \\xcrun ar -rcs "$OLDPWD/$1" *.o
        \\xcrun ranlib "$OLDPWD/$1"
        \\cd "$OLDPWD"
        \\rm -rf "$work_dir"
    ;
    const repack = b.addSystemCommand(&.{ "sh", "-c", script, "--" });
    const output = repack.addOutputFileArg(name);
    repack.addArtifactArg(lib);
    return output;
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
        .name = "oayao",
        .root_module = module,
    });
    lib.entry = .disabled;
    return lib;
}
