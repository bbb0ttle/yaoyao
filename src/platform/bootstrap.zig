//! Platform-specific bootstrap: iOS Swift runtime initialization.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.bootstrap);

const builtin = @import("builtin");

extern fn oayao_swift_bootstrap() void;

/// Initialize platform runtime (triggers Swift bootstrap on iOS).
pub fn bootstrap() void {
    if (builtin.os.tag == .ios) {
        oayao_swift_bootstrap();
    }
}
