const business = @import("core/business.zig");
const Vec2 = business.Vec2;
const random = @import("random.zig");

pub const MAX_LIFESPAN: f32 = 135.0;
pub const MAX_PARTICLE_SIZE: f32 = 12.0;

pub const ParticleOpts = struct {
    immortal: bool = false,
    floating: bool = false,
    beat: bool = false,
    meteor: bool = false,
    size: f32 = MAX_PARTICLE_SIZE,
};

pub const Particle = struct {
    pos: Vec2,
    vel: Vec2,
    acc: Vec2,
    lifespan: f32,
    size: f32,
    age: f32,
    birth_sec: f32,
    alive: bool,
    immortal: bool,
    floating: bool,
    beat: bool,
    meteor: bool,
    next_free: usize,

    fn init(pos: Vec2, birth_sec: f32, opts: ParticleOpts) Particle {
        return Particle{
            .pos = pos.copy(),
            .vel = Vec2{ .x = random.randomRange(-1.0, 1.0), .y = random.randomRange(-1.0, 0.0) },
            .acc = Vec2{ .x = 0.0, .y = 0.08 },
            .lifespan = MAX_LIFESPAN,
            .size = opts.size,
            .age = 0.0,
            .birth_sec = birth_sec,
            .alive = true,
            .immortal = opts.immortal,
            .floating = opts.floating,
            .beat = opts.beat,
            .meteor = opts.meteor,
            .next_free = PARTICLE_POOL_SIZE,
        };
    }

    pub fn update(self: *Particle, elapsed: f32, dpr: f32) void {
        if (!self.alive) return;
        if (self.meteor) return;
        self.age += 0.2;

        if (!self.immortal and !self.floating) {
            self.vel = self.vel.add(self.acc);
            self.lifespan -= 2.0;
        }

        if (self.floating) {
            self.pos.x += @sin(self.age) / 6.0;
            self.pos.y += @cos(self.age) / 6.0;
        } else {
            self.pos = self.pos.add(self.vel);
        }

        if (self.beat) {
            const real_age = elapsed - self.birth_sec;
            self.size = business.breath(real_age, (MAX_PARTICLE_SIZE - 3.0) * dpr, MAX_PARTICLE_SIZE * dpr);
        }

        if (!self.immortal and self.lifespan < 0.0) {
            self.alive = false;
        }
    }

    fn isDead(self: Particle) bool {
        return !self.alive;
    }
};

const PARTICLE_POOL_SIZE: usize = 5000;
pub var particle_pool: [PARTICLE_POOL_SIZE]Particle = undefined;
pub var particle_pool_len: usize = 0;

// Free list head index. PARTICLE_POOL_SIZE means empty list.
var free_head: usize = PARTICLE_POOL_SIZE;

// Indices of particles that are still alive after the current frame's updates.
// Used by renderers to avoid scanning dead slots.
pub var alive_indices: [PARTICLE_POOL_SIZE]usize = undefined;
pub var alive_count: usize = 0;

pub fn collectAlive() void {
    alive_count = 0;
    free_head = PARTICLE_POOL_SIZE;
    for (0..particle_pool_len) |i| {
        if (particle_pool[i].alive) {
            alive_indices[alive_count] = i;
            alive_count += 1;
        } else {
            particle_pool[i].next_free = free_head;
            free_head = i;
        }
    }
}

pub fn allocParticle(pos: Vec2, elapsed: f32, opts: ParticleOpts) *Particle {
    if (free_head < PARTICLE_POOL_SIZE) {
        const idx = free_head;
        free_head = particle_pool[idx].next_free;
        particle_pool[idx] = Particle.init(pos, elapsed, opts);
        return &particle_pool[idx];
    }
    if (particle_pool_len < PARTICLE_POOL_SIZE) {
        const idx = particle_pool_len;
        particle_pool_len += 1;
        particle_pool[idx] = Particle.init(pos, elapsed, opts);
        return &particle_pool[idx];
    }
    // Pool exhausted — overwrite slot 0 as last resort.
    particle_pool[0] = Particle.init(pos, elapsed, opts);
    return &particle_pool[0];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = @import("std").testing;

fn resetPool() void {
    particle_pool_len = 0;
    free_head = PARTICLE_POOL_SIZE;
    alive_count = 0;
}

test "Particle.init sets fields" {
    const pos = Vec2{ .x = 10.0, .y = 20.0 };
    const p = Particle.init(pos, 100.0, .{ .immortal = true, .size = 12.0 });
    try testing.expectApproxEqAbs(10.0, p.pos.x, 1e-6);
    try testing.expectApproxEqAbs(20.0, p.pos.y, 1e-6);
    try testing.expect(p.immortal);
    try testing.expect(p.alive);
    try testing.expectApproxEqAbs(MAX_LIFESPAN, p.lifespan, 1e-6);
    try testing.expectApproxEqAbs(12.0, p.size, 1e-6);
}

test "Particle.death on lifespan exhausted" {
    var p = Particle.init(Vec2{ .x = 0, .y = 0 }, 0.0, .{});
    p.lifespan = -1.0;
    p.update(0.0, 1.0);
    try testing.expect(!p.alive);
}

test "immortal particle does not die" {
    var p = Particle.init(Vec2{ .x = 0, .y = 0 }, 0.0, .{ .immortal = true });
    p.lifespan = -1.0;
    p.update(0.0, 1.0);
    try testing.expect(p.alive);
}

test "allocParticle from empty pool" {
    resetPool();
    const pos = Vec2{ .x = 1.0, .y = 2.0 };
    const p = allocParticle(pos, 0.0, .{ .immortal = true });
    try testing.expect(p.alive);
    try testing.expectApproxEqAbs(1.0, p.pos.x, 1e-6);
    try testing.expectEqual(@as(usize, 1), particle_pool_len);
}

test "allocParticle reuses freed slot" {
    resetPool();
    const p0 = allocParticle(Vec2{ .x = 0, .y = 0 }, 0.0, .{});
    _ = allocParticle(Vec2{ .x = 1, .y = 1 }, 0.0, .{}); // fills slot 1
    p0.alive = false;
    collectAlive(); // moves p0's index to free list
    const p2 = allocParticle(Vec2{ .x = 2, .y = 2 }, 0.0, .{});
    // p2 should reuse the same slot as p0
    try testing.expectEqual(p0, p2);
}

test "collectAlive counts correctly" {
    resetPool();
    _ = allocParticle(Vec2{ .x = 0, .y = 0 }, 0.0, .{ .immortal = true });
    _ = allocParticle(Vec2{ .x = 1, .y = 1 }, 0.0, .{});
    particle_pool[1].alive = false;
    collectAlive();
    try testing.expectEqual(@as(usize, 1), alive_count);
    try testing.expectEqual(@as(usize, 0), alive_indices[0]);
}
