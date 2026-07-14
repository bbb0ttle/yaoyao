const std = @import("std");
const Vec2 = @import("types.zig").Vec2;

pub fn create_heart_pos(t: f32) Vec2 {
    const s = @sin(t);
    const x = 2.0 * s * s * s;
    const y = -(2.0 * ((13.0 * @cos(t) - 5.0 * @cos(2.0 * t) - 2.0 * @cos(3.0 * t) - @cos(4.0 * t)) / 16.0));
    return Vec2{ .x = x, .y = y };
}

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "create_heart_pos at t=0" {
    const p = create_heart_pos(0.0);
    try testing.expectApproxEqAbs(0.0, p.x, 1e-6);
    try testing.expectApproxEqAbs(-0.625, p.y, 1e-6);
}

test "create_heart_pos at t=pi" {
    const p = create_heart_pos(std.math.pi);
    try testing.expectApproxEqAbs(0.0, p.x, 1e-4);
    try testing.expect(p.y > 0.0);
}

test "breath within bounds" {
    for (0..100) |i| {
        const t = @as(f32, @floatFromInt(i)) * 0.01;
        const v = breath(t, 10.0, 20.0);
        try testing.expect(v >= 10.0);
        try testing.expect(v <= 20.0);
    }
}

test "scale linear" {
    try testing.expectApproxEqAbs(50.0, scale(100.0, 200.0, 100.0), 1e-6);
    try testing.expectApproxEqAbs(0.0, scale(0.0, 200.0, 100.0), 1e-6);
    try testing.expectApproxEqAbs(75.0, scale(150.0, 200.0, 100.0), 1e-6);
}
