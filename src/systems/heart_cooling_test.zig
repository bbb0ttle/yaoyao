const std = @import("std");
const testing = std.testing;
const heart_cooling = @import("heart_cooling.zig");
const HeartCooling = heart_cooling.HeartCooling;
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const Rng = @import("../random.zig").Rng;

fn test_pool() !ParticlePool {
    return ParticlePool.init(testing.allocator, 500);
}

test "cooling: intensity decays monotonically from one" {
    try testing.expectApproxEqAbs(@as(f32, 1.0), heart_cooling.intensity(0.0, 4.0), 1e-6);
    var age: f32 = 0.0;
    while (age < 3.0) : (age += 0.1) {
        try testing.expect(heart_cooling.intensity(age + 0.1, 4.0) < heart_cooling.intensity(age, 4.0));
    }
}

test "cooling: landing burst fires immediately on add" {
    var pool = try test_pool();
    defer pool.deinit();
    var cooling = HeartCooling.init(testing.allocator);
    defer cooling.deinit();
    var rng = Rng.init(999);

    try cooling.add(10.0, 10.0, "evt-1", 0.0, &pool, &rng, 1.0);
    const burst_count = pool.get_alive_count();
    try testing.expect(burst_count >= 16 and burst_count <= 24);
    try testing.expectEqual(@as(usize, 1), cooling.emitters.items.len);
}

test "cooling: continuous emission adds 2 particles per frame" {
    var pool = try test_pool();
    defer pool.deinit();
    var cooling = HeartCooling.init(testing.allocator);
    defer cooling.deinit();
    var rng = Rng.init(42);

    try cooling.add(50.0, 50.0, "evt-2", 0.0, &pool, &rng, 2.0);
    const after_landing = pool.get_alive_count();
    cooling.update(0.12, &pool, &rng, 2.0);
    // One frame of update should add exactly 2 particles (no deaths yet)
    try testing.expectEqual(after_landing + 2, pool.get_alive_count());
}

test "cooling: emitter is retired after cooling duration" {
    var pool = try test_pool();
    defer pool.deinit();
    var cooling = HeartCooling.init(testing.allocator);
    defer cooling.deinit();
    var rng = Rng.init(1);

    try cooling.add(10.0, 10.0, "evt-4", 0.0, &pool, &rng, 1.0);
    cooling.update(7.0, &pool, &rng, 1.0);
    try testing.expectEqual(@as(usize, 0), cooling.emitters.items.len);
}

test "cooling: cancel stops emission for a removed heart" {
    var pool = try test_pool();
    defer pool.deinit();
    var cooling = HeartCooling.init(testing.allocator);
    defer cooling.deinit();
    var rng = Rng.init(3);

    try cooling.add(10.0, 10.0, "evt-5", 0.0, &pool, &rng, 1.0);
    const after_landing = pool.get_alive_count();
    cooling.cancel("evt-5");
    try testing.expectEqual(@as(usize, 0), cooling.emitters.items.len);

    var t: f32 = 0.0;
    while (t < 3.0) : (t += 1.0 / 60.0) {
        cooling.update(t, &pool, &rng, 1.0);
    }
    // Particle lifecycles are driven by the render loop, not the pool, so
    // in this harness a cancelled emitter simply adds nothing new.
    try testing.expectEqual(after_landing, pool.get_alive_count());
}

test "cooling: clear drops all emitters" {
    var pool = try test_pool();
    defer pool.deinit();
    var cooling = HeartCooling.init(testing.allocator);
    defer cooling.deinit();
    var rng = Rng.init(5);

    try cooling.add(10.0, 10.0, "evt-6", 0.0, &pool, &rng, 1.0);
    try cooling.add(20.0, 20.0, "evt-7", 0.0, &pool, &rng, 1.0);
    cooling.clear();
    try testing.expectEqual(@as(usize, 0), cooling.emitters.items.len);
}
