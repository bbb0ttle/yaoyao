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

test "breath_cycle hits extremes at quarter and three-quarter period" {
    // phase = sec * 2pi / period: sin peaks at T/4, troughs at 3T/4
    try testing.expectApproxEqAbs(20.0, math.breath_cycle(1.0, 4.0, 10.0, 20.0), 1e-5);
    try testing.expectApproxEqAbs(10.0, math.breath_cycle(3.0, 4.0, 10.0, 20.0), 1e-5);
    // breath is breath_cycle at the heartbeat period (2/3 s)
    const sec = 0.37;
    try testing.expectApproxEqAbs(
        math.breath(sec, 10.0, 20.0),
        math.breath_cycle(sec, 2.0 / 3.0, 10.0, 20.0),
        1e-6,
    );
}

test "scale linear" {
    try testing.expectApproxEqAbs(50.0, math.scale(100.0, 200.0, 100.0), 1e-6);
    try testing.expectApproxEqAbs(0.0, math.scale(0.0, 200.0, 100.0), 1e-6);
    try testing.expectApproxEqAbs(75.0, math.scale(150.0, 200.0, 100.0), 1e-6);
}

test "drag_step decays speed exponentially with distance travelled" {
    // Quadratic drag over path length D lands at exactly v0·e^(-k·D):
    // blazing entry, gentle final approach, like a meteor braking.
    const v0: f32 = 8.0;
    const v_end: f32 = 3.0;
    const dist: f32 = 1200.0;
    const k = @log(v0 / v_end) / dist;

    var v = v0;
    var x: f32 = 0.0;
    var max_step_drop: f32 = 0.0;
    while (x < dist) {
        const nv = math.drag_step(v, k);
        max_step_drop = @max(max_step_drop, v - nv);
        x += nv;
        v = nv;
    }
    try testing.expectApproxEqAbs(v_end, v, 0.05);
    // Deceleration is sharpest at entry (drag ∝ v²), never later.
    try testing.expect(max_step_drop > 0.0);
    try testing.expect(max_step_drop < 0.2);
}

test "spring_step converges to target and rests" {
    var s = math.SpringState{ .x = 0.0, .y = 0.0, .vx = 0.0, .vy = 0.0 };
    for (0..600) |_| {
        s = math.spring_step(s.x, s.y, s.vx, s.vy, 100.0, 50.0, 0.15, 0.3);
    }
    try testing.expectApproxEqAbs(100.0, s.x, 0.01);
    try testing.expectApproxEqAbs(50.0, s.y, 0.01);
    try testing.expectApproxEqAbs(0.0, s.vx, 0.01);
    try testing.expectApproxEqAbs(0.0, s.vy, 0.01);
}

test "spring_step overshoots along incoming velocity, then settles back" {
    // At the target with inward velocity: inertia carries the position past
    // the target (follow-through) before the spring pulls it back to rest.
    var s = math.SpringState{ .x = 100.0, .y = 50.0, .vx = 2.0, .vy = 0.0 };
    var max_x: f32 = 100.0;
    for (0..600) |_| {
        s = math.spring_step(s.x, s.y, s.vx, s.vy, 100.0, 50.0, 0.15, 0.3);
        max_x = @max(max_x, s.x);
    }
    try testing.expect(max_x > 105.0);
    try testing.expectApproxEqAbs(100.0, s.x, 0.01);
    try testing.expectApproxEqAbs(0.0, s.vx, 0.01);
}
