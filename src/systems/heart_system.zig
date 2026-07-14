const std = @import("std");
const Vec2 = @import("../core/types.zig").Vec2;
const math = @import("../core/math.zig");
const Particle = @import("../particles/particle.zig").Particle;
const ParticleOpts = @import("../particles/particle.zig").ParticleOpts;
const MAX_PARTICLE_SIZE = @import("../particles/particle.zig").MAX_PARTICLE_SIZE;
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const Rng = @import("../random.zig").Rng;

const CONTOUR_COUNT: usize = 30;

const ContourPoint = struct {
    base_x: f32,
    base_y: f32,
    immortal: *Particle,
};

pub const HeartSystem = struct {
    contour: [CONTOUR_COUNT]ContourPoint,
    float_pair: [2]*Particle,
    birth_sec: f32,
    cx: f32,
    cy: f32,
    canvas_h: f32,
    dpr: f32,
    spawn_counter: u32,

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
    ) HeartSystem {
        pool.reset();

        var self = HeartSystem{
            .contour = undefined,
            .float_pair = undefined,
            .birth_sec = elapsed,
            .cx = cx,
            .cy = cy,
            .canvas_h = canvas_h,
            .dpr = dpr,
            .spawn_counter = 0,
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
            const pos = Vec2{ .x = hp.x * hscale + hscale + cx, .y = hp.y * hscale + hscale + cy };
            self.contour[i] = ContourPoint{
                .base_x = hp.x,
                .base_y = hp.y,
                .immortal = pool.alloc_particle(pos, elapsed, .{ .immortal = true, .size = MAX_PARTICLE_SIZE * dpr }, rng),
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

    pub fn update(self: *HeartSystem, elapsed: f32, pool: *ParticlePool, rng: *Rng) void {
        const dpr = self.dpr;
        const scale_val = math.breath(elapsed - self.birth_sec, 50.0 * dpr, 60.0 * dpr);
        const size_val = math.breath(elapsed - self.birth_sec, 10.0 * dpr, 15.0 * dpr);

        self.spawn_counter += 1;
        const spawn_frame = self.spawn_counter % 2 == 0;

        for (&self.contour) |*cp| {
            cp.immortal.pos.x = cp.base_x * scale_val + 50.0 * dpr + self.cx;
            cp.immortal.pos.y = cp.base_y * scale_val + 50.0 * dpr + self.cy - 5.0 * dpr;
            cp.immortal.size = size_val;

            if (spawn_frame) {
                _ = pool.alloc_particle(cp.immortal.pos, elapsed, .{ .size = MAX_PARTICLE_SIZE * dpr }, rng);
            }
        }
    }

    pub fn fill_contour_positions(self: *const HeartSystem, buf: []Vec2) void {
        for (&self.contour, 0..) |*cp, i| {
            buf[i] = cp.immortal.pos;
        }
    }

    pub fn center_x(self: *const HeartSystem) f32 {
        return self.cx;
    }

    pub fn center_y(self: *const HeartSystem) f32 {
        return self.cy;
    }

    pub fn float_pair_left(self: *HeartSystem) *Particle {
        return self.float_pair[0];
    }

    pub fn float_pair_right(self: *HeartSystem) *Particle {
        return self.float_pair[1];
    }
};
