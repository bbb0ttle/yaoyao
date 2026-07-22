//! Nebula background: two screen-spanning fbm cloud layers.
//!
//! Each layer is one huge gaussian-less blob (shader shape 3 = continuous
//! fbm density field). The near layer is brighter and drifts faster, the
//! far layer dimmer and slower — a deep, seamless sky. Layers breathe over
//! 30–80 second cycles.

const std = @import("std");

const Vec2 = @import("../core/types.zig").Vec2;
const Particle = @import("../particles/particle.zig").Particle;
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const Rng = @import("../random.zig").Rng;

const LAYER_COUNT: usize = 2;

/// Fixed two-layer nebula; trivial per-frame cost.
pub const NebulaSystem = struct {
    const Self = @This();

    layers: [LAYER_COUNT]*Particle,
    drifts: [LAYER_COUNT]Vec2,
    phases: [LAYER_COUNT]f32,
    breath_speeds: [LAYER_COUNT]f32,
    base_alphas: [LAYER_COUNT]f32,

    pub fn init(pool: *ParticlePool, rng: *Rng, w: f32, h: f32, dpr: f32, elapsed: f32) Self {
        const diag = @sqrt(w * w + h * h);
        const cx = w / 2.0;
        const cy = h / 2.0;

        var self = Self{
            .layers = undefined,
            .drifts = undefined,
            .phases = undefined,
            .breath_speeds = undefined,
            .base_alphas = undefined,
        };

        for (0..LAYER_COUNT) |i| {
            const fi: f32 = @floatFromInt(i);
            const size = diag * (0.75 + 0.15 * fi);
            const layer = pool.alloc_particle(
                Vec2{
                    .x = cx + rng.random_range(-0.05, 0.05) * diag,
                    .y = cy + rng.random_range(-0.05, 0.05) * diag,
                },
                elapsed,
                .{ .immortal = true, .blob = true, .size = size },
                rng,
            );
            layer.set_vel(0, 0);
            layer.set_acc(0, 0);
            self.layers[i] = layer;

            // Far layer: dimmer, slower. Near layer: brighter, quicker.
            const nearness = 1.0 - fi / @as(f32, LAYER_COUNT - 1);
            const angle = rng.random_range(0.0, 2.0 * std.math.pi);
            const drift_speed = rng.random_range(0.03, 0.08) * dpr * (0.5 + nearness);
            self.drifts[i] = Vec2{ .x = @cos(angle) * drift_speed, .y = @sin(angle) * drift_speed };
            self.phases[i] = rng.random_range(0.0, 2.0 * std.math.pi);
            self.breath_speeds[i] = rng.random_range(0.08, 0.2);
            self.base_alphas[i] = 0.18 + 0.10 * nearness;
        }
        return self;
    }

    /// Very slow breathing; gentle drift bounced within the coverage margin
    /// so each layer always spans the full screen.
    pub fn update(self: *Self, elapsed: f32, w: f32, h: f32) void {
        const diag = @sqrt(w * w + h * h);
        const cx = w / 2.0;
        const cy = h / 2.0;

        for (0..LAYER_COUNT) |i| {
            const layer = self.layers[i];
            const wave = 0.5 + 0.5 * @sin(elapsed * self.breath_speeds[i] + self.phases[i]);
            layer.set_alpha_scale(self.base_alphas[i] * (0.7 + 0.3 * wave));

            const margin = layer.get_size() - diag / 2.0;
            const next_x = layer.pos_x() + self.drifts[i].x;
            const next_y = layer.pos_y() + self.drifts[i].y;
            if (@abs(next_x - cx) > margin) self.drifts[i].x = -self.drifts[i].x;
            if (@abs(next_y - cy) > margin) self.drifts[i].y = -self.drifts[i].y;
            layer.translate(self.drifts[i].x, self.drifts[i].y);
        }
    }

    /// Kill all layers (pool compaction reclaims the slots).
    pub fn clear(self: *Self) void {
        for (0..LAYER_COUNT) |i| {
            self.layers[i].set_alive(false);
        }
    }
};
