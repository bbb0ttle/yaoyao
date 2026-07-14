const std = @import("std");
const Particle = @import("particle.zig").Particle;
const ParticleOpts = @import("particle.zig").ParticleOpts;
const Vec2 = @import("../core/types.zig").Vec2;
const Rng = @import("../random.zig").Rng;

const SENTINEL: usize = std.math.maxInt(usize);

pub const ParticlePool = struct {
    particles: []Particle,
    alive_indices: []usize,
    alive_count: usize,
    len: usize,
    free_head: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !ParticlePool {
        const particles = try allocator.alloc(Particle, capacity);
        const alive_indices = try allocator.alloc(usize, capacity);
        return ParticlePool{
            .particles = particles,
            .alive_indices = alive_indices,
            .alive_count = 0,
            .len = 0,
            .free_head = SENTINEL,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ParticlePool) void {
        self.allocator.free(self.particles);
        self.allocator.free(self.alive_indices);
    }

    pub fn reset(self: *ParticlePool) void {
        self.len = 0;
        self.free_head = SENTINEL;
        self.alive_count = 0;
    }

    pub fn collect_alive(self: *ParticlePool) void {
        self.alive_count = 0;
        self.free_head = SENTINEL;
        for (0..self.len) |i| {
            if (self.particles[i].flags.alive) {
                self.alive_indices[self.alive_count] = i;
                self.alive_count += 1;
            } else {
                self.particles[i]._storage = .{ .next_free = self.free_head };
                self.free_head = i;
            }
        }
    }

    pub fn alloc_particle(self: *ParticlePool, pos: Vec2, elapsed: f32, opts: ParticleOpts, rng: *Rng) *Particle {
        if (self.free_head < SENTINEL) {
            const idx = self.free_head;
            self.free_head = self.particles[idx]._storage.next_free;
            self.particles[idx] = Particle.init(pos, elapsed, opts, rng);
            return &self.particles[idx];
        }
        if (self.len < self.particles.len) {
            const idx = self.len;
            self.len += 1;
            self.particles[idx] = Particle.init(pos, elapsed, opts, rng);
            return &self.particles[idx];
        }
        self.particles[0] = Particle.init(pos, elapsed, opts, rng);
        return &self.particles[0];
    }

    pub fn alive_slice(self: *const ParticlePool) []usize {
        return self.alive_indices[0..self.alive_count];
    }

    pub fn get_particle(self: *ParticlePool, idx: usize) *Particle {
        return &self.particles[idx];
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

fn _test_pool() !ParticlePool {
    return ParticlePool.init(testing.allocator, 100);
}

test "alloc_particle from empty pool" {
    var pool = try _test_pool();
    defer pool.deinit();
    var rng = Rng.init(12345);
    const pos = Vec2{ .x = 1.0, .y = 2.0 };
    const p = pool.alloc_particle(pos, 0.0, .{ .immortal = true }, &rng);
    try testing.expect(p.flags.alive);
    try testing.expectApproxEqAbs(1.0, p.pos.x, 1e-6);
    try testing.expectEqual(@as(usize, 1), pool.len);
}

test "alloc_particle reuses freed slot" {
    var pool = try _test_pool();
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
    var pool = try _test_pool();
    defer pool.deinit();
    var rng = Rng.init(12345);
    _ = pool.alloc_particle(Vec2{ .x = 0, .y = 0 }, 0.0, .{ .immortal = true }, &rng);
    _ = pool.alloc_particle(Vec2{ .x = 1, .y = 1 }, 0.0, .{}, &rng);
    pool.particles[1].set_alive(false);
    pool.collect_alive();
    try testing.expectEqual(@as(usize, 1), pool.alive_count);
    try testing.expectEqual(@as(usize, 0), pool.alive_indices[0]);
}
