//! Particle instance with position, velocity, lifecycle, and rendering flags.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.particle);

const Vec2 = @import("../core/types.zig").Vec2;
const Rng = @import("../random.zig").Rng;

pub const MAX_LIFESPAN: f32 = 155.0;
pub const MAX_PARTICLE_SIZE: f32 = 12.0;
const FADE_IN_PER_FRAME: f32 = 1.0 / 45.0;

/// Optional configuration for particle creation with sensible defaults.
pub const ParticleOpts = struct {
    immortal: bool = false,
    floating: bool = false,
    beat: bool = false,
    meteor: bool = false,
    blob: bool = false,
    size: f32 = MAX_PARTICLE_SIZE,
};

const ParticleFlags = packed struct(u8) {
    is_alive: bool,
    is_immortal: bool,
    is_floating: bool,
    is_beat: bool,
    is_meteor: bool,
    is_fading_out: bool,
    is_blob: bool,
    is_fading_in: bool,
};

/// A pooled particle with position, velocity, flags, and tagged union storage.
pub const Particle = struct {
    const Self = @This();

    pos: Vec2,
    vel: Vec2,
    lifespan: f32,
    size: f32,
    age: f32,
    flags: ParticleFlags,
    acc: Vec2,
    size_scale: f32,
    alpha_scale: f32,
    _storage: union {
        birth_sec: f32,
        next_free: usize,
    },

    pub fn init(pos: Vec2, birth_sec: f32, opts: ParticleOpts, rng: *Rng) Self {
        return Self{
            .pos = pos,
            .vel = Vec2{ .x = rng.random_range(-1.0, 1.0), .y = rng.random_range(-1.0, 0.0) },
            .acc = Vec2{ .x = 0.0, .y = 0.08 },
            .lifespan = MAX_LIFESPAN,
            .size = opts.size,
            .age = 0.0,
            .flags = .{
                .is_alive = true,
                .is_immortal = opts.immortal,
                .is_floating = opts.floating,
                .is_beat = opts.beat,
                .is_meteor = opts.meteor,
                .is_fading_out = false,
                .is_blob = opts.blob,
                .is_fading_in = false,
            },
            ._storage = .{ .birth_sec = birth_sec },
            .size_scale = 1.0,
            .alpha_scale = 1.0,
        };
    }

    pub fn update(self: *Self, elapsed: f32, dpr: f32) void {
        if (!self.flags.is_alive) return;
        if (self.flags.is_meteor) return;
        self.age += 0.2;

        if (self.flags.is_fading_in) {
            self.alpha_scale = @min(1.0, self.alpha_scale + FADE_IN_PER_FRAME);
            if (self.alpha_scale >= 1.0) {
                self.flags.is_fading_in = false;
            }
        }

        if (!self.flags.is_immortal and (!self.flags.is_floating or self.flags.is_fading_out)) {
            if (!self.flags.is_floating) {
                self.vel = self.vel.add(self.acc);
            }
            self.lifespan -= 2.0;
        }

        if (self.flags.is_floating) {
            self.pos.x += @sin(self.age) / 6.0;
            self.pos.y += @cos(self.age) / 6.0;
        } else {
            self.pos = self.pos.add(self.vel);
        }

        if (self.flags.is_beat) {
            const math = @import("../core/math.zig");
            const real_age = elapsed - self._storage.birth_sec;
            self.size = math.breath(real_age, (MAX_PARTICLE_SIZE - 3.0) * dpr, MAX_PARTICLE_SIZE * dpr) * self.size_scale;
        }

        if (!self.flags.is_immortal and self.lifespan < 0.0) {
            self.flags.is_alive = false;
        }
    }

    pub fn get_pos(self: Self) Vec2 {
        return self.pos;
    }

    pub fn pos_x(self: Self) f32 {
        return self.pos.x;
    }

    pub fn pos_y(self: Self) f32 {
        return self.pos.y;
    }

    pub fn set_pos(self: *Particle, x: f32, y: f32) void {
        self.pos.x = x;
        self.pos.y = y;
    }

    pub fn vel_x(self: Self) f32 {
        return self.vel.x;
    }

    pub fn vel_y(self: Self) f32 {
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

    pub fn acc_y(self: Self) f32 {
        return self.acc.y;
    }

    pub fn get_lifespan(self: Self) f32 {
        return self.lifespan;
    }

    pub fn set_lifespan(self: *Particle, l: f32) void {
        self.lifespan = l;
    }

    pub fn get_size(self: Self) f32 {
        return self.size;
    }

    pub fn set_size(self: *Particle, s: f32) void {
        self.size = s;
    }

    pub fn get_size_scale(self: Self) f32 {
        return self.size_scale;
    }

    pub fn set_size_scale(self: *Particle, s: f32) void {
        self.size_scale = s;
    }

    pub fn get_alpha_scale(self: Self) f32 {
        return self.alpha_scale;
    }

    pub fn set_alpha_scale(self: *Particle, s: f32) void {
        self.alpha_scale = s;
    }

    pub fn is_alive(self: Self) bool {
        return self.flags.is_alive;
    }

    pub fn set_alive(self: *Particle, alive: bool) void {
        self.flags.is_alive = alive;
    }

    pub fn is_immortal(self: Self) bool {
        return self.flags.is_immortal;
    }

    pub fn set_immortal(self: *Particle, immortal: bool) void {
        self.flags.is_immortal = immortal;
    }

    pub fn is_floating(self: Self) bool {
        return self.flags.is_floating;
    }

    pub fn set_floating(self: *Particle, v: bool) void {
        self.flags.is_floating = v;
    }

    pub fn is_beat(self: Self) bool {
        return self.flags.is_beat;
    }

    pub fn set_beat(self: *Particle, v: bool) void {
        self.flags.is_beat = v;
    }

    pub fn is_meteor(self: Self) bool {
        return self.flags.is_meteor;
    }

    pub fn set_meteor(self: *Particle, v: bool) void {
        self.flags.is_meteor = v;
    }

    pub fn is_fading_out(self: Self) bool {
        return self.flags.is_fading_out;
    }

    pub fn is_blob(self: Self) bool {
        return self.flags.is_blob;
    }

    pub fn is_fading_in(self: Self) bool {
        return self.flags.is_fading_in;
    }

    pub fn set_fading_in(self: *Particle, v: bool) void {
        self.flags.is_fading_in = v;
    }
    pub fn set_fading_out(self: *Particle, v: bool) void {
        self.flags.is_fading_out = v;
    }

    pub fn set_birth_sec(self: *Particle, sec: f32) void {
        self._storage = .{ .birth_sec = sec };
    }

    pub fn get_birth_sec(self: Self) f32 {
        return self._storage.birth_sec;
    }

    pub fn get_next_free(self: Self) usize {
        return self._storage.next_free;
    }

    pub fn set_next_free(self: *Particle, n: usize) void {
        self._storage = .{ .next_free = n };
    }

    pub fn translate(self: *Particle, dx: f32, dy: f32) void {
        self.pos.x += dx;
        self.pos.y += dy;
    }

    pub fn translate_by_vel(self: *Self) void {
        self.pos.x += self.vel.x;
        self.pos.y += self.vel.y;
    }
};
