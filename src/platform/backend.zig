const sokol = @import("sokol");
const sg = sokol.gfx;

pub fn detect_gpu_backend() sg.Backend {
    var backend = sg.queryBackend();
    if (backend == .METAL_SIMULATOR) {
        backend = .METAL_IOS;
    }
    return backend;
}
