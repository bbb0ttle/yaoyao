//! Heart contour rendering system with floating pair animation.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.heart_system);

const Vec2 = @import("../core/types.zig").Vec2;
const math = @import("../core/math.zig");
const Particle = @import("../particles/particle.zig").Particle;
const ParticleOpts = @import("../particles/particle.zig").ParticleOpts;
const MAX_PARTICLE_SIZE = @import("../particles/particle.zig").MAX_PARTICLE_SIZE;
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const Rng = @import("../random.zig").Rng;

const CONTOUR_COUNT: usize = 30;

// Calm breathing cadence: one full inhale-exhale cycle per 4 seconds,
// much slower than the ~0.67s heartbeat pulse so the two modes read apart.
const BREATH_PERIOD_SEC: f32 = 3.7;

/// Big-heart animation style; values are part of the C ABI.
pub const MotionMode = enum(u32) {
    beat = 0,
    breath = 1,
};

const ContourPoint = struct {
    base_x: f32,
    base_y: f32,
    immortal: *Particle,
};

/// Heart contour with 30 immortal contour points and two floating pair particles.
pub const HeartSystem = struct {
    const Self = @This();

    contour: [CONTOUR_COUNT]ContourPoint,
    float_pair: [2]*Particle,
    birth_sec: f32,
    cx: f32,
    cy: f32,
    canvas_h: f32,
    dpr: f32,
    spawn_counter: u32,
    opacity: f32,
    motion: MotionMode,
    size_scale: f32,

    pub fn init(
        pool: *ParticlePool,
        rng: *Rng,
        elapsed: f32,
        cx: f32,
        cy: f32,
        canvas_h: f32,
        fp_x: f32,
        fp_y: f32,
        dpr: f32,
    ) Self {
        pool.reset();

        var self = Self{
            .contour = undefined,
            .float_pair = undefined,
            .birth_sec = elapsed,
            .cx = cx,
            .cy = cy,
            .canvas_h = canvas_h,
            .dpr = dpr,
            .spawn_counter = 0,
            .opacity = 1.0,
            .motion = .beat,
            .size_scale = 1.0,
        };

        const start: f32 = 0.0;
        const end: f32 = 2.0 * std.math.pi;
        const step: f32 = (end - start) / @as(f32, @floatFromInt(CONTOUR_COUNT));
        const hscale: f32 = 50.0 * dpr;

        var i: usize = 0;
        var t: f32 = start;
        while (i < CONTOUR_COUNT) : ({
            i += 1;
            t += step;
        }) {
            const hp = math.create_heart_pos(t);
            const px = hp.x * hscale + hscale + cx;
            const py = hp.y * hscale + hscale + cy;
            self.contour[i] = ContourPoint{
                .base_x = hp.x,
                .base_y = hp.y,
                .immortal = pool.alloc_particle(Vec2{ .x = px, .y = py }, elapsed, .{ .immortal = true, .size = MAX_PARTICLE_SIZE * dpr }, rng),
            };
        }

        self.float_pair[0] = pool.alloc_particle(Vec2{ .x = fp_x, .y = fp_y }, elapsed, .{
            .immortal = true,
            .floating = true,
            .beat = true,
            .size = MAX_PARTICLE_SIZE * dpr,
        }, rng);
        self.float_pair[1] = pool.alloc_particle(Vec2{ .x = fp_x + 7.0 * dpr, .y = fp_y - 2.0 * dpr }, elapsed, .{
            .immortal = true,
            .floating = true,
            .beat = true,
            .size = MAX_PARTICLE_SIZE * dpr,
        }, rng);

        return self;
    }

    pub fn update(self: *Self, elapsed: f32, pool: *ParticlePool, rng: *Rng) void {
        const dpr = self.dpr;
        const t = elapsed - self.birth_sec;
        const base = 50.0 * dpr * self.size_scale;
        const scale_val = switch (self.motion) {
            .beat => math.breath(t, base, base * 1.2),
            .breath => math.breath_cycle(t, BREATH_PERIOD_SEC, base, base * 1.2),
        };
        const size_val = switch (self.motion) {
            .beat => math.breath(t, 10.0 * dpr * self.size_scale, 15.0 * dpr * self.size_scale),
            .breath => math.breath_cycle(t, BREATH_PERIOD_SEC, 10.0 * dpr * self.size_scale, 15.0 * dpr * self.size_scale),
        };
        // Breath mode also swells the alpha gently, like the reference
        // breathing-circle demo; beat mode stays at constant alpha.
        const alpha_val = self.opacity * switch (self.motion) {
            .beat => 1.0,
            .breath => math.breath_cycle(t, BREATH_PERIOD_SEC, 0.7, 1.0),
        };

        self.spawn_counter += 1;
        const spawn_frame = self.spawn_counter % 2 == 0;

        for (&self.contour) |*cp| {
            cp.immortal.set_pos(
                cp.base_x * scale_val + base + self.cx,
                cp.base_y * scale_val + base + self.cy - 5.0 * dpr,
            );
            cp.immortal.set_size(size_val);
            cp.immortal.set_alpha_scale(alpha_val);

            if (spawn_frame) {
                const trail = pool.alloc_particle(cp.immortal.get_pos(), elapsed, .{ .size = MAX_PARTICLE_SIZE * dpr }, rng);
                trail.set_alpha_scale(alpha_val);
            }
        }
    }

    pub fn set_opacity(self: *Self, opacity: f32) void {
        self.opacity = opacity;
    }

    pub fn set_motion(self: *Self, motion: MotionMode) void {
        self.motion = motion;
    }

    pub fn set_size_scale(self: *Self, size_scale: f32) void {
        self.size_scale = size_scale;
    }

    pub fn set_cy(self: *Self, cy: f32) void {
        self.cy = cy;
    }

    pub fn fill_contour_positions(self: *const Self, buf: []Vec2) void {
        for (&self.contour, 0..) |*cp, i| {
            buf[i] = Vec2{ .x = cp.immortal.pos_x(), .y = cp.immortal.pos_y() };
        }
    }

    /// Whether a circle at (x, y) overlaps any contour point's current extent.
    pub fn touches_contour(self: *const Self, x: f32, y: f32, radius: f32) bool {
        for (&self.contour) |*cp| {
            const dx = x - cp.immortal.pos_x();
            const dy = y - cp.immortal.pos_y();
            const reach = radius + cp.immortal.get_size();
            if (dx * dx + dy * dy < reach * reach) return true;
        }
        return false;
    }

    pub fn center_x(self: *const Self) f32 {
        return self.cx;
    }

    pub fn center_y(self: *const Self) f32 {
        return self.cy;
    }

    pub fn float_pair_left(self: *Self) *Particle {
        return self.float_pair[0];
    }

    pub fn float_pair_right(self: *Self) *Particle {
        return self.float_pair[1];
    }
};
