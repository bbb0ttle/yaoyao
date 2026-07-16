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
    fading_out: bool,
    _pad: u2 = 0,
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
                .fading_out = false,
            },
            ._storage = .{ .birth_sec = birth_sec },
            .size_scale = 1.0,
        };
    }

    pub fn update(self: *Particle, elapsed: f32, dpr: f32) void {
        if (!self.flags.alive) return;
        if (self.flags.meteor) return;
        self.age += 0.2;

        if (!self.flags.immortal and (!self.flags.floating or self.flags.fading_out)) {
            if (!self.flags.floating) {
                self.vel = self.vel.add(self.acc);
            }
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

    pub fn get_pos(self: Particle) Vec2 {
        return self.pos;
    }

    pub fn pos_x(self: Particle) f32 {
        return self.pos.x;
    }

    pub fn pos_y(self: Particle) f32 {
        return self.pos.y;
    }

    pub fn set_pos(self: *Particle, x: f32, y: f32) void {
        self.pos.x = x;
        self.pos.y = y;
    }

    pub fn vel_x(self: Particle) f32 {
        return self.vel.x;
    }

    pub fn vel_y(self: Particle) f32 {
        return self.vel.y;
    }

    pub fn set_vel(self: *Particle, x: f32, y: f32) void {
        self.vel.x = x;
        self.vel.y = y;
    }

    pub fn set_acc(self: *Particle, x: f32, y: f32) void {
        self.acc.x = x;
        self.acc.y = y;
    }

    pub fn get_lifespan(self: Particle) f32 {
        return self.lifespan;
    }

    pub fn set_lifespan(self: *Particle, l: f32) void {
        self.lifespan = l;
    }

    pub fn get_size(self: Particle) f32 {
        return self.size;
    }

    pub fn set_size(self: *Particle, s: f32) void {
        self.size = s;
    }

    pub fn set_size_scale(self: *Particle, s: f32) void {
        self.size_scale = s;
    }

    pub fn is_alive(self: Particle) bool {
        return self.flags.alive;
    }

    pub fn set_alive(self: *Particle, alive: bool) void {
        self.flags.alive = alive;
    }

    pub fn is_immortal(self: Particle) bool {
        return self.flags.immortal;
    }

    pub fn set_immortal(self: *Particle, immortal: bool) void {
        self.flags.immortal = immortal;
    }

    pub fn is_floating(self: Particle) bool {
        return self.flags.floating;
    }

    pub fn set_floating(self: *Particle, v: bool) void {
        self.flags.floating = v;
    }

    pub fn is_beat(self: Particle) bool {
        return self.flags.beat;
    }

    pub fn set_beat(self: *Particle, v: bool) void {
        self.flags.beat = v;
    }

    pub fn is_meteor(self: Particle) bool {
        return self.flags.meteor;
    }

    pub fn set_meteor(self: *Particle, v: bool) void {
        self.flags.meteor = v;
    }

    pub fn is_fading_out(self: Particle) bool {
        return self.flags.fading_out;
    }

    pub fn set_fading_out(self: *Particle, v: bool) void {
        self.flags.fading_out = v;
    }

    pub fn set_birth_sec(self: *Particle, sec: f32) void {
        self._storage = .{ .birth_sec = sec };
    }

    pub fn get_birth_sec(self: Particle) f32 {
        return self._storage.birth_sec;
    }

    pub fn get_next_free(self: Particle) usize {
        return self._storage.next_free;
    }

    pub fn set_next_free(self: *Particle, n: usize) void {
        self._storage = .{ .next_free = n };
    }

    pub fn translate(self: *Particle, dx: f32, dy: f32) void {
        self.pos.x += dx;
        self.pos.y += dy;
    }

    pub fn translate_by_vel(self: *Particle) void {
        self.pos.x += self.vel.x;
        self.pos.y += self.vel.y;
    }
};
