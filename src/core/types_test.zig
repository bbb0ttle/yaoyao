const testing = @import("std").testing;
const Vec2 = @import("types.zig").Vec2;

test "Vec2.add" {
    const a = Vec2{ .x = 1.0, .y = 2.0 };
    const b = Vec2{ .x = 3.0, .y = -1.0 };
    const r = a.add(b);
    try testing.expectApproxEqAbs(4.0, r.x, 1e-6);
    try testing.expectApproxEqAbs(1.0, r.y, 1e-6);
}
