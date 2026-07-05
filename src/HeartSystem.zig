const std = @import("std");
const types = @import("types.zig");
const Rgba = types.Rgba;
const Vec2 = types.Vec2;
const math = @import("math.zig");
const FrameBuffer = @import("FrameBuffer.zig").FrameBuffer;
const particle = @import("Particle.zig");

const CONTOUR_COUNT: usize = 30;

const ContourPoint = struct {
    index: f32,
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
            const hp = math.createHeartPos(t);
            const pos = Vec2{ .x = hp.x * hscale + hscale + cx, .y = hp.y * hscale + hscale + cy };
            self.contour[i] = ContourPoint{
                .index = t,
                .immortal = particle.allocParticle(pos, elapsed, .{ .kind = .immortal, .size = particle.MAX_PARTICLE_SIZE * dpr }),
            };
        }

        self.float_pair[0] = particle.allocParticle(Vec2{ .x = fp_x, .y = fp_y }, elapsed, .{
            .kind = .floating_beat,
            .size = particle.MAX_PARTICLE_SIZE * dpr,
        });
        self.float_pair[1] = particle.allocParticle(Vec2{ .x = fp_x + 7.0 * dpr, .y = fp_y - 2.0 * dpr }, elapsed, .{
            .kind = .floating_beat,
            .size = particle.MAX_PARTICLE_SIZE * dpr,
        });

        return self;
    }

    pub fn update(self: *HeartSystem, elapsed: f32) void {
        const dpr = self.dpr;
        const scale_val = math.breath(elapsed - self.birth_sec, 50.0 * dpr, 60.0 * dpr);
        const size_val = math.breath(elapsed - self.birth_sec, 10.0 * dpr, 15.0 * dpr);

        for (&self.contour) |*cp| {
            const hp = math.createHeartPos(cp.index);
            cp.immortal.pos.x = hp.x * scale_val + 50.0 * dpr + self.cx;
            cp.immortal.pos.y = hp.y * scale_val + 50.0 * dpr + self.cy - 5.0 * dpr;
            cp.immortal.size = size_val;

            _ = particle.allocParticle(cp.immortal.pos.copy(), elapsed, .{ .size = particle.MAX_PARTICLE_SIZE * dpr });
        }

        var i: usize = 0;
        while (i < particle.particle_pool_len) : (i += 1) {
            var p = &particle.particle_pool[i];
            if (p.alive) {
                p.update(elapsed, dpr);
            }
        }
    }

    pub fn render(self: HeartSystem, fb: FrameBuffer, elapsed: f32, t: f32) void {
        _ = elapsed;
        const stroke_width: f32 = 2.0 * self.dpr;
        var i: usize = 0;
        while (i < particle.particle_pool_len) : (i += 1) {
            const p = &particle.particle_pool[i];
            if (!p.alive) continue;

            const max_alpha: f32 = if (p.kind != .normal and p.lifespan >= particle.MAX_LIFESPAN) 255.0 else math.scale(p.lifespan, particle.MAX_LIFESPAN, 200.0);

            const px: i32 = @as(i32, @intFromFloat(p.pos.x));
            const py: i32 = @as(i32, @intFromFloat(p.pos.y));
            const display_size: f32 = math.scale(p.lifespan, particle.MAX_LIFESPAN, p.size);

            var stroke_color = Rgba.heart_stroke;
            stroke_color.a = @intFromFloat(@min(255.0, p.lifespan) * t);
            fb.drawHeartParticle(px, py, display_size + stroke_width, stroke_color);

            var fill = Rgba.heart_fill;
            fill.a = @intFromFloat(max_alpha * t);
            fb.drawHeartParticle(px, py, display_size, fill);
        }
    }
};
