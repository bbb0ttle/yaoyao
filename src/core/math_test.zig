const std = @import("std");
const math = @import("math.zig");
const testing = std.testing;

test "create_heart_pos at t=0" {
    const p = math.create_heart_pos(0.0);
    try testing.expectApproxEqAbs(0.0, p.x, 1e-6);
    try testing.expectApproxEqAbs(-0.625, p.y, 1e-6);
}

test "create_heart_pos at t=pi" {
    const p = math.create_heart_pos(std.math.pi);
    try testing.expectApproxEqAbs(0.0, p.x, 1e-4);
    try testing.expect(p.y > 0.0);
}

test "breath within bounds" {
    for (0..100) |i| {
        const t = @as(f32, @floatFromInt(i)) * 0.01;
        const v = math.breath(t, 10.0, 20.0);
        try testing.expect(v >= 10.0);
        try testing.expect(v <= 20.0);
    }
}

test "smooth_breath within bounds and hits extremes" {
    for (0..100) |i| {
        const t = @as(f32, @floatFromInt(i)) * 0.01;
        const v = math.smooth_breath(t, 10.0, 20.0);
        try testing.expect(v >= 10.0);
        try testing.expect(v <= 20.0);
    }
    // sin(pi/2) = 1 at sec = 1/6 → max; sin(3pi/2) = -1 at sec = 1/2 → min
    try testing.expectApproxEqAbs(20.0, math.smooth_breath(1.0 / 6.0, 10.0, 20.0), 1e-5);
    try testing.expectApproxEqAbs(10.0, math.smooth_breath(0.5, 10.0, 20.0), 1e-5);
}

test "scale linear" {
    try testing.expectApproxEqAbs(50.0, math.scale(100.0, 200.0, 100.0), 1e-6);
    try testing.expectApproxEqAbs(0.0, math.scale(0.0, 200.0, 100.0), 1e-6);
    try testing.expectApproxEqAbs(75.0, math.scale(150.0, 200.0, 100.0), 1e-6);
}
