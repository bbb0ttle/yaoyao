const Vec2 = @import("../core/types.zig").Vec2;
const Rng = @import("../random.zig").Rng;

pub const MAX_LIFESPAN: f32 = 155.0;
pub const MAX_PARTICLE_SIZE: f32 = 12.0;

pub const ParticleOpts = struct {
    immortal: bool = false,
    floating: bool = false,
    beat: bool = false,
    meteor: bool = false,
    size: f32 = MAX_PARTICLE_SIZE,
};

const ParticleFlags = packed struct(u8) {
    alive: bool,
    immortal: bool,
    floating: bool,
    beat: bool,
    meteor: bool,
    _pad: u3 = 0,
};

pub const Particle = struct {
    pos: Vec2,
    vel: Vec2,
    lifespan: f32,
    size: f32,
    age: f32,
    flags: ParticleFlags,
    acc: Vec2,
    size_scale: f32,
    _storage: union {
        birth_sec: f32,
        next_free: usize,
    },

    pub fn init(pos: Vec2, birth_sec: f32, opts: ParticleOpts, rng: *Rng) Particle {
        return Particle{
            .pos = pos,
            .vel = Vec2{ .x = rng.random_range(-1.0, 1.0), .y = rng.random_range(-1.0, 0.0) },
            .acc = Vec2{ .x = 0.0, .y = 0.08 },
            .lifespan = MAX_LIFESPAN,
            .size = opts.size,
            .age = 0.0,
            .flags = .{
                .alive = true,
                .immortal = opts.immortal,
                .floating = opts.floating,
                .beat = opts.beat,
                .meteor = opts.meteor,
            },
            ._storage = .{ .birth_sec = birth_sec },
            .size_scale = 1.0,
        };
    }

    pub fn update(self: *Particle, elapsed: f32, dpr: f32) void {
        if (!self.flags.alive) return;
        if (self.flags.meteor) return;
        self.age += 0.2;

        if (!self.flags.immortal and !self.flags.floating) {
            self.vel = self.vel.add(self.acc);
            self.lifespan -= 2.0;
        }

        if (self.flags.floating) {
            self.pos.x += @sin(self.age) / 6.0;
            self.pos.y += @cos(self.age) / 6.0;
        } else {
            self.pos = self.pos.add(self.vel);
        }

        if (self.flags.beat) {
            const math = @import("../core/math.zig");
            const real_age = elapsed - self._storage.birth_sec;
            self.size = math.breath(real_age, (MAX_PARTICLE_SIZE - 3.0) * dpr, MAX_PARTICLE_SIZE * dpr) * self.size_scale;
        }

        if (!self.flags.immortal and self.lifespan < 0.0) {
            self.flags.alive = false;
        }
    }

    pub fn is_alive(self: Particle) bool {
        return self.flags.alive;
    }

    pub fn is_immortal(self: Particle) bool {
        return self.flags.immortal;
    }

    pub fn set_alive(self: *Particle, alive: bool) void {
        self.flags.alive = alive;
    }

    pub fn set_immortal(self: *Particle, immortal: bool) void {
        self.flags.immortal = immortal;
    }

    pub fn set_birth_sec(self: *Particle, sec: f32) void {
        self._storage = .{ .birth_sec = sec };
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = @import("std").testing;

test "Particle.init sets fields" {
    var rng = Rng.init(12345);
    const pos = Vec2{ .x = 10.0, .y = 20.0 };
    const p = Particle.init(pos, 100.0, .{ .immortal = true, .size = 12.0 }, &rng);
    try testing.expectApproxEqAbs(10.0, p.pos.x, 1e-6);
    try testing.expectApproxEqAbs(20.0, p.pos.y, 1e-6);
    try testing.expect(p.flags.immortal);
    try testing.expect(p.flags.alive);
    try testing.expectApproxEqAbs(MAX_LIFESPAN, p.lifespan, 1e-6);
    try testing.expectApproxEqAbs(12.0, p.size, 1e-6);
}

test "Particle death on lifespan exhausted" {
    var rng = Rng.init(12345);
    var p = Particle.init(Vec2{ .x = 0, .y = 0 }, 0.0, .{}, &rng);
    p.lifespan = -1.0;
    p.update(0.0, 1.0);
    try testing.expect(!p.flags.alive);
}

test "immortal particle does not die" {
    var rng = Rng.init(12345);
    var p = Particle.init(Vec2{ .x = 0, .y = 0 }, 0.0, .{ .immortal = true }, &rng);
    p.lifespan = -1.0;
    p.update(0.0, 1.0);
    try testing.expect(p.flags.alive);
}
