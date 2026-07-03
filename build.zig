const std = @import("std");

pub fn build(b: *std.Build) void {
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
}
