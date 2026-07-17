//! Heart curve parametric equations and breathing animation math.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.math);

const Vec2 = @import("types.zig").Vec2;

/// Parametric heart curve: returns a Vec2 on the heart contour at parameter t.
pub fn create_heart_pos(t: f32) Vec2 {
    const s = @sin(t);
    const x = 2.0 * s * s * s;
    const y = -(2.0 * ((13.0 * @cos(t) - 5.0 * @cos(2.0 * t) - 2.0 * @cos(3.0 * t) - @cos(4.0 * t)) / 16.0));
    return Vec2{ .x = x, .y = y };
}

/// Smooth breathing oscillation between min and max over time.
pub fn breath(sec: f32, min: f32, max: f32) f32 {
    const e = std.math.e;
    const a = 1.0 / e;
    const b = e - a;
    const s = (max - min) / b;
    const exp_val = @exp(@sin(sec * 3.0 * std.math.pi));
    return @mulAdd(f32, exp_val, s, min - a * s);
}

pub fn scale(val: f32, a: f32, b: f32) f32 {
    return val * b / a;
}
