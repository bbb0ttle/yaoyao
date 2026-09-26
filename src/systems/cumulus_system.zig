//! Cumulus sky: two depth layers of billowing cloud puffs riding a slow
//! wind. Each puff is one instanced fbm blob (shader shape 4) with a dome
//! envelope — bright crests, shaded base, like a summer afternoon.

const std = @import("std");

const Vec2 = @import("../core/types.zig").Vec2;
const Particle = @import("../particles/particle.zig").Particle;
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const Rng = @import("../random.zig").Rng;

const PUFF_COUNT: usize = 7;
const FAR_COUNT: usize = 4; // the first four puffs form the far layer

/// Fixed puff field; per-frame cost is trivial.
pub const CumulusSystem = struct {
    const Self = @This();

    puffs: [PUFF_COUNT]*Particle,
    speeds: [PUFF_COUNT]f32,
    phases: [PUFF_COUNT]f32,
    breath_speeds: [PUFF_COUNT]f32,
    base_alphas: [PUFF_COUNT]f32,

    pub fn init(pool: *ParticlePool, rng: *Rng, w: f32, h: f32, dpr: f32, elapsed: f32) Self {
        var self = Self{
            .puffs = undefined,
            .speeds = undefined,
            .phases = undefined,
            .breath_speeds = undefined,
            .base_alphas = undefined,
        };

        for (0..PUFF_COUNT) |i| {
            const near = i >= FAR_COUNT;
            const size = (if (near) rng.random_range(150.0, 240.0) else rng.random_range(90.0, 150.0)) * dpr;
            const puff = pool.alloc_particle(Vec2{
                .x = rng.random_range(0.0, w),
                .y = rng.random_range(h * 0.05, h * 0.45),
            }, elapsed, .{ .immortal = true, .sky = .cumulus, .size = size }, rng);
            puff.set_vel(0, 0);
            puff.set_acc(0, 0);
            // birth_sec doubles as the puff's fbm seed (carried to the
            // shader via stroke_a); immortal puffs have no other use for it.
            puff.set_birth_sec(rng.random_range(0.0, 500.0));
            self.puffs[i] = puff;

            // Near layer: bigger, brighter, a touch faster — parallax.
            self.speeds[i] = (if (near) rng.random_range(0.22, 0.4) else rng.random_range(0.08, 0.18)) * dpr;
            self.phases[i] = rng.random_range(0.0, 2.0 * std.math.pi);
            self.breath_speeds[i] = rng.random_range(0.06, 0.15);
            self.base_alphas[i] = if (near) 0.75 else 0.45;
        }
        return self;
    }

    /// Wind drift with left-edge wraparound and a slow alpha breath.
    pub fn update(self: *Self, elapsed: f32, w: f32, h: f32) void {
        _ = h;
        for (0..PUFF_COUNT) |i| {
            const puff = self.puffs[i];
            const wave = 0.5 + 0.5 * @sin(elapsed * self.breath_speeds[i] + self.phases[i]);
            puff.set_alpha_scale(self.base_alphas[i] * (0.85 + 0.15 * wave));

            const size = puff.get_size();
            var x = puff.pos_x() + self.speeds[i];
            if (x - size > w) x = -size;
            puff.set_pos(x, puff.pos_y());
        }
    }

    /// Kill all puffs (pool compaction reclaims the slots).
    pub fn clear(self: *Self) void {
        for (0..PUFF_COUNT) |i| {
            self.puffs[i].set_alive(false);
        }
    }
};
