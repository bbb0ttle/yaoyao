//! GPU backend detection and simulator workaround.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.backend);

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
