const std = @import("std");
const business = @import("core/business.zig");
const Rgba = business.Rgba;
const Vec2 = business.Vec2;
const particle = @import("Particle.zig");

const CONTOUR_COUNT: usize = 30;

const ContourPoint = struct {
    base_x: f32,
    base_y: f32,
    immortal: *particle.Particle,
};

pub const HeartSystem = struct {
    contour: [CONTOUR_COUNT]ContourPoint,
    float_pair: [2]*particle.Particle,
    birth_sec: f32,
    cx: f32,
    cy: f32,
    canvas_h: f32,
    dpr: f32,
    spawn_counter: u32,

    pub fn init(elapsed: f32, cx: f32, cy: f32, canvas_h: f32, fp_x: f32, fp_y: f32, dpr: f32) HeartSystem {
        particle.particle_pool_len = 0;

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
            const hp = business.createHeartPos(t);
            const pos = Vec2{ .x = hp.x * hscale + hscale + cx, .y = hp.y * hscale + hscale + cy };
            self.contour[i] = ContourPoint{
                .base_x = hp.x,
                .base_y = hp.y,
                .immortal = particle.allocParticle(pos, elapsed, .{ .immortal = true, .size = particle.MAX_PARTICLE_SIZE * dpr }),
            };
        }

        self.float_pair[0] = particle.allocParticle(Vec2{ .x = fp_x, .y = fp_y }, elapsed, .{
            .immortal = true,
            .floating = true,
            .beat = true,
            .size = particle.MAX_PARTICLE_SIZE * dpr,
        });
        self.float_pair[1] = particle.allocParticle(Vec2{ .x = fp_x + 7.0 * dpr, .y = fp_y - 2.0 * dpr }, elapsed, .{
            .immortal = true,
            .floating = true,
            .beat = true,
            .size = particle.MAX_PARTICLE_SIZE * dpr,
        });

        return self;
    }

    pub fn update(self: *HeartSystem, elapsed: f32) void {
        const dpr = self.dpr;
        const scale_val = business.breath(elapsed - self.birth_sec, 50.0 * dpr, 60.0 * dpr);
        const size_val = business.breath(elapsed - self.birth_sec, 10.0 * dpr, 15.0 * dpr);

        self.spawn_counter += 1;
        const spawn_frame = self.spawn_counter % 2 == 0;

        for (&self.contour) |*cp| {
            cp.immortal.pos.x = cp.base_x * scale_val + 50.0 * dpr + self.cx;
            cp.immortal.pos.y = cp.base_y * scale_val + 50.0 * dpr + self.cy - 5.0 * dpr;
            cp.immortal.size = size_val;

            if (spawn_frame) {
                _ = particle.allocParticle(cp.immortal.pos, elapsed, .{ .size = particle.MAX_PARTICLE_SIZE * dpr });
            }
        }

    }
};
