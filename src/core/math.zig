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

/// exp(sin) oscillation between min and max over one period: the exponential
/// mapping dwells gently at the extremes, reading as a calm held breath.
pub fn breath_cycle(sec: f32, period_sec: f32, min: f32, max: f32) f32 {
    const phase = sec * 2.0 * std.math.pi / period_sec;
    const e = std.math.e;
    const a = 1.0 / e;
    const s = (max - min) / (e - a);
    return @mulAdd(f32, @exp(@sin(phase)), s, min - a * s);
}

/// Heartbeat pulse: the exp(sin) curve at a fast ~90bpm rate.
pub fn breath(sec: f32, min: f32, max: f32) f32 {
    return breath_cycle(sec, 2.0 / 3.0, min, max);
}

pub fn scale(val: f32, a: f32, b: f32) f32 {
    return val * b / a;
}
