//! Cumulonimbus sky: towering thunderheads (shader shape 8). A few massive
//! anvil-crowned towers loom over the upper sky; heavy clouds barely drift.
//! Two depth layers — distant towers are smaller, dimmer, slower.

const std = @import("std");

const Vec2 = @import("../core/types.zig").Vec2;
const Particle = @import("../particles/particle.zig").Particle;
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const Rng = @import("../random.zig").Rng;

const TOWER_COUNT: usize = 5;
const FAR_COUNT: usize = 2; // the first two towers form the far layer

/// Fixed tower field; per-frame cost is trivial.
pub const CumulonimbusSystem = struct {
    const Self = @This();

    towers: [TOWER_COUNT]*Particle,
    speeds: [TOWER_COUNT]f32,
    phases: [TOWER_COUNT]f32,
    breath_speeds: [TOWER_COUNT]f32,
    base_alphas: [TOWER_COUNT]f32,

    pub fn init(pool: *ParticlePool, rng: *Rng, w: f32, h: f32, dpr: f32, elapsed: f32) Self {
        var self = Self{
            .towers = undefined,
            .speeds = undefined,
            .phases = undefined,
            .breath_speeds = undefined,
            .base_alphas = undefined,
        };

        for (0..TOWER_COUNT) |i| {
            const near = i >= FAR_COUNT;
            const size = (if (near) rng.random_range(360.0, 520.0) else rng.random_range(240.0, 340.0)) * dpr;
            const tower = pool.alloc_particle(Vec2{
                .x = rng.random_range(0.0, w),
                .y = if (near) rng.random_range(h * 0.08, h * 0.25) else rng.random_range(h * 0.02, h * 0.15),
            }, elapsed, .{ .immortal = true, .sky = .cumulonimbus, .size = size }, rng);
            tower.set_vel(0, 0);
            tower.set_acc(0, 0);
            // birth_sec doubles as the tower's fbm seed (carried to the
            // shader via stroke_a).
            tower.set_birth_sec(rng.random_range(0.0, 500.0));
            self.towers[i] = tower;

            // px/frame × dpr — heavy towers drift slowly; far layer slower.
            self.speeds[i] = (if (near) rng.random_range(0.12, 0.22) else rng.random_range(0.06, 0.12)) * dpr;
            self.phases[i] = rng.random_range(0.0, 2.0 * std.math.pi);
            self.breath_speeds[i] = rng.random_range(0.04, 0.09);
            self.base_alphas[i] = if (near) rng.random_range(0.65, 0.85) else rng.random_range(0.45, 0.6);
        }
        return self;
    }

    /// Slow drift with left-edge wraparound and a faint breath.
    pub fn update(self: *Self, elapsed: f32, w: f32, h: f32) void {
        _ = h;
        for (0..TOWER_COUNT) |i| {
            const tower = self.towers[i];
            const wave = 0.5 + 0.5 * @sin(elapsed * self.breath_speeds[i] + self.phases[i]);
            tower.set_alpha_scale(self.base_alphas[i] * (0.88 + 0.12 * wave));

            const size = tower.get_size();
            var x = tower.pos_x() + self.speeds[i];
            if (x - size > w) x = -size;
            tower.set_pos(x, tower.pos_y());
        }
    }

    /// Kill all towers (pool compaction reclaims the slots).
    pub fn clear(self: *Self) void {
        for (0..TOWER_COUNT) |i| {
            self.towers[i].set_alive(false);
        }
    }
};
