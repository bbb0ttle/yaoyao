//! GPU backend detection and simulator workaround.


const sokol = @import("sokol");
const sg = sokol.gfx;

/// Detect the active GPU backend, mapping METAL_SIMULATOR to METAL_IOS.
pub fn detect_gpu_backend() sg.Backend {
    var backend = sg.queryBackend();
    if (backend == .METAL_SIMULATOR) {
        backend = .METAL_IOS;
    }
    return backend;
}
