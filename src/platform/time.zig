//! Platform wall-clock access.

const std = @import("std");

/// Current Unix time in milliseconds (real-time clock).
pub fn unix_ms() f64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
    return @as(f64, @floatFromInt(ts.sec)) * 1000.0 + @as(f64, @floatFromInt(ts.nsec)) / 1_000_000.0;
}
