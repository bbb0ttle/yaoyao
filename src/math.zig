const std = @import("std");
const Vec2 = @import("types.zig").Vec2;

/// Parametric heart curve. t in [0, 2π], result in [-2, 2] for x, roughly [-2.5, 1.5] for y.
pub fn createHeartPos(t: f32) Vec2 {
    const s = @sin(t);
    const x = 2.0 * s * s * s;
    const y = -(2.0 * ((13.0 * @cos(t) - 5.0 * @cos(2.0 * t) - 2.0 * @cos(3.0 * t) - @cos(4.0 * t)) / 16.0));
    return Vec2{ .x = x, .y = y };
}

/// Smooth periodic oscillation suitable for breathing effects.
/// Returns a value in [min, max] that oscillates with period ~0.67s.
pub fn breath(sec: f32, min: f32, max: f32) f32 {
    const e = std.math.e;
    const a = 1.0 / e;
    const b = e - a;
    return (@exp(@sin(sec * 3.0 * std.math.pi)) - a) * (max - min) / b + min;
}

/// Linear interpolation: returns val * b / a.
pub fn scale(val: f32, a: f32, b: f32) f32 {
    return val * b / a;
}

test "createHeartPos at t=0" {
    const pos = createHeartPos(0.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), pos.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -0.625), pos.y, 0.01);
}

test "createHeartPos at t=pi/2" {
    const pos = createHeartPos(std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), pos.x, 0.001);
}

test "breath range" {
    const val = breath(0.0, 10.0, 20.0);
    try std.testing.expect(val >= 10.0);
    try std.testing.expect(val <= 20.0);
}

test "breath oscillation" {
    const a = breath(0.0, 0.0, 1.0);
    const b = breath(0.1, 0.0, 1.0);
    try std.testing.expect(a != b);
}

test "scale interpolation" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), scale(50.0, 100.0, 1.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), scale(0.0, 100.0, 1.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), scale(100.0, 100.0, 1.0), 0.001);
}
