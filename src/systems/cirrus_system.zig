//! Cirrus sky: high ice-crystal streaks (shader shape 5). Each streak is a
//! thin wind-sheared wisp; streaks slide at different speeds so the field
//! reads as layered wind shear.

const std = @import("std");

const Vec2 = @import("../core/types.zig").Vec2;
const Particle = @import("../particles/particle.zig").Particle;
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const Rng = @import("../random.zig").Rng;

const STREAK_COUNT: usize = 6;

/// Fixed streak field; per-frame cost is trivial.
pub const CirrusSystem = struct {
    const Self = @This();

    streaks: [STREAK_COUNT]*Particle,
    speeds: [STREAK_COUNT]f32,
    phases: [STREAK_COUNT]f32,
    breath_speeds: [STREAK_COUNT]f32,
    base_alphas: [STREAK_COUNT]f32,

    pub fn init(pool: *ParticlePool, rng: *Rng, w: f32, h: f32, dpr: f32, elapsed: f32) Self {
        var self = Self{
            .streaks = undefined,
            .speeds = undefined,
            .phases = undefined,
            .breath_speeds = undefined,
            .base_alphas = undefined,
        };

        for (0..STREAK_COUNT) |i| {
            const size = rng.random_range(180.0, 320.0) * dpr;
            const streak = pool.alloc_particle(Vec2{
                .x = rng.random_range(0.0, w),
                .y = rng.random_range(h * 0.05, h * 0.4),
            }, elapsed, .{ .immortal = true, .sky = .cirrus, .size = size }, rng);
            streak.set_vel(0, 0);
            streak.set_acc(0, 0);
            // birth_sec doubles as the streak's fbm seed (carried to the
            // shader via stroke_a).
            streak.set_birth_sec(rng.random_range(0.0, 500.0));
            self.streaks[i] = streak;

            // Widely varying speeds read as wind shear between layers.
            self.speeds[i] = rng.random_range(0.15, 0.5) * dpr;
            self.phases[i] = rng.random_range(0.0, 2.0 * std.math.pi);
            self.breath_speeds[i] = rng.random_range(0.08, 0.2);
            self.base_alphas[i] = rng.random_range(0.5, 0.8);
        }
        return self;
    }

    /// Sheared drift with left-edge wraparound and a faint shimmer.
    pub fn update(self: *Self, elapsed: f32, w: f32, h: f32) void {
        _ = h;
        for (0..STREAK_COUNT) |i| {
            const streak = self.streaks[i];
            const wave = 0.5 + 0.5 * @sin(elapsed * self.breath_speeds[i] + self.phases[i]);
            streak.set_alpha_scale(self.base_alphas[i] * (0.85 + 0.15 * wave));

            const size = streak.get_size();
            var x = streak.pos_x() + self.speeds[i];
            if (x - size > w) x = -size;
            streak.set_pos(x, streak.pos_y());
        }
    }

    /// Kill all streaks (pool compaction reclaims the slots).
    pub fn clear(self: *Self) void {
        for (0..STREAK_COUNT) |i| {
            self.streaks[i].set_alive(false);
        }
    }
};
