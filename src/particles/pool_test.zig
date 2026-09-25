const std = @import("std");
const testing = std.testing;
const ParticlePool = @import("pool.zig").ParticlePool;
const Vec2 = @import("../core/types.zig").Vec2;
const Rng = @import("../random.zig").Rng;

fn test_pool() !ParticlePool {
    return ParticlePool.init(testing.allocator, 100);
}

test "alloc_particle from empty pool" {
    var pool = try test_pool();
    defer pool.deinit();
    var rng = Rng.init(12345);
    const pos = Vec2{ .x = 1.0, .y = 2.0 };
    const p = pool.alloc_particle(pos, 0.0, .{ .immortal = true }, &rng);
    try testing.expect(p.is_alive());
    try testing.expectApproxEqAbs(1.0, p.pos_x(), 1e-6);
    try testing.expectEqual(@as(usize, 1), pool.get_len());
}

test "alloc_particle reuses freed slot" {
    var pool = try test_pool();
    defer pool.deinit();
    var rng = Rng.init(12345);
    const p0 = pool.alloc_particle(Vec2{ .x = 0, .y = 0 }, 0.0, .{}, &rng);
    _ = pool.alloc_particle(Vec2{ .x = 1, .y = 1 }, 0.0, .{}, &rng);
    p0.set_alive(false);
    pool.collect_alive();
    const p2 = pool.alloc_particle(Vec2{ .x = 2, .y = 2 }, 0.0, .{}, &rng);
    try testing.expectEqual(p0, p2);
}

test "collect_alive counts correctly" {
    var pool = try test_pool();
    defer pool.deinit();
    var rng = Rng.init(12345);
    _ = pool.alloc_particle(Vec2{ .x = 0, .y = 0 }, 0.0, .{ .immortal = true }, &rng);
    const p1 = pool.alloc_particle(Vec2{ .x = 1, .y = 1 }, 0.0, .{}, &rng);
    p1.set_alive(false);
    pool.collect_alive();
    try testing.expectEqual(@as(usize, 1), pool.get_alive_count());
    try testing.expectEqual(@as(usize, 0), pool.alive_slice()[0]);
}

test "alloc_particle at capacity recycles a non-immortal slot" {
    var pool = try ParticlePool.init(testing.allocator, 2);
    defer pool.deinit();
    var rng = Rng.init(12345);
    const p0 = pool.alloc_particle(Vec2{ .x = 0, .y = 0 }, 0.0, .{ .immortal = true }, &rng);
    _ = pool.alloc_particle(Vec2{ .x = 1, .y = 1 }, 0.0, .{}, &rng);

    // Third alloc exceeds capacity: the mortal slot is recycled, the
    // immortal one is kept, and the alive list stays duplicate-free.
    const p2 = pool.alloc_particle(Vec2{ .x = 2, .y = 2 }, 0.0, .{}, &rng);
    try testing.expectEqual(@as(usize, 2), pool.get_alive_count());
    try testing.expect(p0.is_alive());
    try testing.expectApproxEqAbs(2.0, p2.pos_x(), 1e-6);
    for (pool.alive_slice(), 0..) |ai, i| {
        for (pool.alive_slice()[i + 1 ..]) |aj| {
            try testing.expect(ai != aj);
        }
    }

    // The recycled slot must not appear on the free list later: killing
    // everything and collecting yields exactly one reusable slot per
    // non-immortal particle.
    p2.set_alive(false);
    pool.collect_alive();
    const q0 = pool.alloc_particle(Vec2{ .x = 3, .y = 3 }, 0.0, .{}, &rng);
    try testing.expectApproxEqAbs(3.0, q0.pos_x(), 1e-6);
    try testing.expectEqual(@as(usize, 2), pool.get_alive_count());
}
