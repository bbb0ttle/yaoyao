const testing = @import("std").testing;
const Particle = @import("particle.zig").Particle;
const MAX_LIFESPAN = @import("particle.zig").MAX_LIFESPAN;
const Vec2 = @import("../core/types.zig").Vec2;
const Rng = @import("../random.zig").Rng;

test "Particle.init sets fields" {
    var rng = Rng.init(12345);
    const pos = Vec2{ .x = 10.0, .y = 20.0 };
    const p = Particle.init(pos, 100.0, .{ .immortal = true, .size = 12.0 }, &rng);
    try testing.expectApproxEqAbs(10.0, p.pos_x(), 1e-6);
    try testing.expectApproxEqAbs(20.0, p.pos_y(), 1e-6);
    try testing.expect(p.is_immortal());
    try testing.expect(p.is_alive());
    try testing.expectApproxEqAbs(MAX_LIFESPAN, p.get_lifespan(), 1e-6);
    try testing.expectApproxEqAbs(12.0, p.get_size(), 1e-6);
}

test "Particle death on lifespan exhausted" {
    var rng = Rng.init(12345);
    var p = Particle.init(Vec2{ .x = 0, .y = 0 }, 0.0, .{}, &rng);
    p.set_lifespan(-1.0);
    p.update(0.0, 1.0);
    try testing.expect(!p.is_alive());
}

test "immortal particle does not die" {
    var rng = Rng.init(12345);
    var p = Particle.init(Vec2{ .x = 0, .y = 0 }, 0.0, .{ .immortal = true }, &rng);
    p.set_lifespan(-1.0);
    p.update(0.0, 1.0);
    try testing.expect(p.is_alive());
}

test "fading_out floating particle decrements lifespan and dies" {
    var rng = Rng.init(12345);
    var p = Particle.init(Vec2{ .x = 0, .y = 0 }, 0.0, .{ .floating = true }, &rng);
    p.set_fading_out(true);
    const initial_lifespan = p.get_lifespan();
    p.update(0.0, 1.0);
    try testing.expect(p.get_lifespan() < initial_lifespan);
    try testing.expect(p.is_alive());

    p.set_lifespan(-1.0);
    p.update(0.0, 1.0);
    try testing.expect(!p.is_alive());
}

test "floating particle without fading_out keeps constant lifespan" {
    var rng = Rng.init(12345);
    var p = Particle.init(Vec2{ .x = 0, .y = 0 }, 0.0, .{ .floating = true }, &rng);
    const initial_lifespan = p.get_lifespan();
    p.update(0.0, 1.0);
    try testing.expectApproxEqAbs(initial_lifespan, p.get_lifespan(), 1e-6);
}
