//! Stratocumulus sky: a rolling mid-level deck (shader shape 7). Each patch
//! is one large coverage-thresholded slab; far and near patches overlap into
//! a broken sheet with sunlit gaps. The near layer rides lower and faster —
//! low clouds read as moving.

const std = @import("std");

const Vec2 = @import("../core/types.zig").Vec2;
const Particle = @import("../particles/particle.zig").Particle;
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const Rng = @import("../random.zig").Rng;

const PATCH_COUNT: usize = 10;
const FAR_COUNT: usize = 4; // the first four patches form the far layer

/// Fixed patch field; per-frame cost is trivial.
pub const StratocumulusSystem = struct {
    const Self = @This();

    patches: [PATCH_COUNT]*Particle,
    speeds: [PATCH_COUNT]f32,
    phases: [PATCH_COUNT]f32,
    breath_speeds: [PATCH_COUNT]f32,
    base_alphas: [PATCH_COUNT]f32,

    pub fn init(pool: *ParticlePool, rng: *Rng, w: f32, h: f32, dpr: f32, elapsed: f32) Self {
        var self = Self{
            .patches = undefined,
            .speeds = undefined,
            .phases = undefined,
            .breath_speeds = undefined,
            .base_alphas = undefined,
        };

        for (0..PATCH_COUNT) |i| {
            const near = i >= FAR_COUNT;
            const size = (if (near) rng.random_range(320.0, 500.0) else rng.random_range(200.0, 300.0)) * dpr;
            const patch = pool.alloc_particle(Vec2{
                .x = rng.random_range(0.0, w),
                .y = if (near) rng.random_range(h * 0.15, h * 0.38) else rng.random_range(h * 0.05, h * 0.20),
            }, elapsed, .{ .immortal = true, .sky = .stratocumulus, .size = size }, rng);
            patch.set_vel(0, 0);
            patch.set_acc(0, 0);
            // birth_sec doubles as the patch's fbm + coverage seed (carried
            // to the shader via stroke_a).
            patch.set_birth_sec(rng.random_range(0.0, 500.0));
            self.patches[i] = patch;

            // px/frame × dpr — near layer lower and faster: parallax.
            self.speeds[i] = (if (near) rng.random_range(0.20, 0.35) else rng.random_range(0.10, 0.20)) * dpr;
            self.phases[i] = rng.random_range(0.0, 2.0 * std.math.pi);
            self.breath_speeds[i] = rng.random_range(0.05, 0.12);
            self.base_alphas[i] = if (near) rng.random_range(0.55, 0.75) else rng.random_range(0.35, 0.5);
        }
        return self;
    }

    /// Slow drift with left-edge wraparound and a faint breath.
    pub fn update(self: *Self, elapsed: f32, w: f32, h: f32) void {
        _ = h;
        for (0..PATCH_COUNT) |i| {
            const patch = self.patches[i];
            const wave = 0.5 + 0.5 * @sin(elapsed * self.breath_speeds[i] + self.phases[i]);
            patch.set_alpha_scale(self.base_alphas[i] * (0.85 + 0.15 * wave));

            const size = patch.get_size();
            var x = patch.pos_x() + self.speeds[i];
            if (x - size > w) x = -size;
            patch.set_pos(x, patch.pos_y());
        }
    }

    /// Kill all patches (pool compaction reclaims the slots).
    pub fn clear(self: *Self) void {
        for (0..PATCH_COUNT) |i| {
            self.patches[i].set_alive(false);
        }
    }
};
