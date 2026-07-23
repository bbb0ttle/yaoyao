//! Lenticular sky: smooth lens-shaped clouds (shader shape 6). Unlike the
//! billowy cumulus or wind-sheared cirrus, lenticular clouds are polished,
//! near-stationary lenses that stack in tight formations — the concentric
//! plate-pile look of standing-wave clouds over mountains. Each formation is
//! accompanied by a few small cumulus puffs and a faint cirrus streak, the
//! companion clouds real lenticulars gather around themselves.

const std = @import("std");

const Vec2 = @import("../core/types.zig").Vec2;
const Particle = @import("../particles/particle.zig").Particle;
const SkyKind = @import("../particles/particle.zig").SkyKind;
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const Rng = @import("../random.zig").Rng;

const FORMATION_COUNT: usize = 2;
const LENSES_PER_FORMATION: usize = 3;
const LENS_COUNT: usize = FORMATION_COUNT * LENSES_PER_FORMATION;

const PUFFS_PER_FORMATION: usize = 2; // small cumulus fractus hugging the stack
const STREAKS_PER_FORMATION: usize = 1; // one faint cirrus veil above it
const ACCENTS_PER_FORMATION: usize = PUFFS_PER_FORMATION + STREAKS_PER_FORMATION;
const ACCENT_COUNT: usize = FORMATION_COUNT * ACCENTS_PER_FORMATION;

/// Fixed lens field; per-frame cost is trivial.
pub const LenticularSystem = struct {
    const Self = @This();

    lenses: [LENS_COUNT]*Particle,
    speeds: [LENS_COUNT]f32,
    phases: [LENS_COUNT]f32,
    breath_speeds: [LENS_COUNT]f32,
    base_alphas: [LENS_COUNT]f32,
    base_ys: [LENS_COUNT]f32,
    float_amps: [LENS_COUNT]f32, // px × dpr — vertical bob amplitude
    float_speeds: [LENS_COUNT]f32, // rad/s — slower than breath: a standing wave's slow heave

    accents: [ACCENT_COUNT]*Particle,
    accent_speeds: [ACCENT_COUNT]f32,
    accent_phases: [ACCENT_COUNT]f32,
    accent_breath_speeds: [ACCENT_COUNT]f32,
    accent_base_alphas: [ACCENT_COUNT]f32,

    pub fn init(pool: *ParticlePool, rng: *Rng, w: f32, h: f32, dpr: f32, elapsed: f32) Self {
        var self = Self{
            .lenses = undefined,
            .speeds = undefined,
            .phases = undefined,
            .breath_speeds = undefined,
            .base_alphas = undefined,
            .base_ys = undefined,
            .float_amps = undefined,
            .float_speeds = undefined,
            .accents = undefined,
            .accent_speeds = undefined,
            .accent_phases = undefined,
            .accent_breath_speeds = undefined,
            .accent_base_alphas = undefined,
        };

        for (0..FORMATION_COUNT) |fi| {
            // Each formation centres on a shared x, with stacked lenses at
            // slightly different y offsets and sizes — the concentric
            // plate-pile that defines lenticular clouds.
            const cx = rng.random_range(w * 0.1, w * 0.9);
            const cy = rng.random_range(h * 0.08, h * 0.28);
            // px/frame × dpr ≈ 0.5–1.2 px/s: standing-wave clouds barely drift.
            const formation_speed = rng.random_range(0.008, 0.02) * dpr;
            const formation_phase = rng.random_range(0.0, 2.0 * std.math.pi);
            const formation_breath = rng.random_range(0.04, 0.10);
            var bottom_size: f32 = 0.0;

            for (0..LENSES_PER_FORMATION) |li| {
                const idx = fi * LENSES_PER_FORMATION + li;
                // Largest lens at the bottom of the stack, smallest at the top.
                const base_size: f32 = if (li == 0) 260.0 else if (li == 1) 200.0 else 150.0;
                const size = rng.random_range(base_size * 0.85, base_size * 1.15) * dpr;
                if (li == 0) bottom_size = size;
                // Stack offset: each lens sits slightly above the previous one.
                const y_off: f32 = if (li == 0) 0.0 else if (li == 1) -22.0 else -40.0;
                const x_jitter = rng.random_range(-10.0, 10.0) * dpr;
                const y = cy + y_off * dpr;

                const lens = pool.alloc_particle(Vec2{
                    .x = cx + x_jitter,
                    .y = y,
                }, elapsed, .{ .immortal = true, .sky = .lenticular, .size = size }, rng);
                lens.set_vel(0, 0);
                lens.set_acc(0, 0);
                lens.set_birth_sec(rng.random_range(0.0, 500.0));
                self.lenses[idx] = lens;

                self.speeds[idx] = formation_speed;
                self.phases[idx] = formation_phase + @as(f32, @floatFromInt(li)) * 0.6;
                self.breath_speeds[idx] = formation_breath;
                // Top lenses are slightly more translucent.
                self.base_alphas[idx] = if (li == 0) rng.random_range(0.6, 0.78) else rng.random_range(0.45, 0.65);
                self.base_ys[idx] = y;
                self.float_amps[idx] = rng.random_range(4.0, 10.0) * dpr;
                self.float_speeds[idx] = rng.random_range(0.015, 0.035);
            }

            // Companion clouds: small cumulus puffs flank the stack, one thin
            // cirrus streak veils it from above. They ride the same wind a
            // touch faster — only the standing-wave lenses are pinned.
            for (0..ACCENTS_PER_FORMATION) |ai| {
                const idx = fi * ACCENTS_PER_FORMATION + ai;
                var pos: Vec2 = undefined;
                var size: f32 = undefined;
                var alpha: f32 = undefined;
                var sky: SkyKind = undefined;
                if (ai < PUFFS_PER_FORMATION) {
                    const side: f32 = if (ai == 0) -1.0 else 1.0;
                    pos = Vec2{
                        .x = cx + side * rng.random_range(0.5, 1.1) * bottom_size,
                        .y = cy + rng.random_range(10.0, 40.0) * dpr,
                    };
                    size = rng.random_range(40.0, 80.0) * dpr;
                    alpha = rng.random_range(0.30, 0.48);
                    sky = .cumulus;
                } else {
                    pos = Vec2{
                        .x = cx + rng.random_range(-0.3, 0.3) * bottom_size,
                        .y = cy - rng.random_range(60.0, 110.0) * dpr,
                    };
                    size = rng.random_range(120.0, 180.0) * dpr;
                    alpha = rng.random_range(0.18, 0.30);
                    sky = .cirrus;
                }

                const accent = pool.alloc_particle(pos, elapsed, .{ .immortal = true, .sky = sky, .size = size }, rng);
                accent.set_vel(0, 0);
                accent.set_acc(0, 0);
                // birth_sec doubles as the shader's fbm seed (stroke_a).
                accent.set_birth_sec(rng.random_range(0.0, 500.0));
                self.accents[idx] = accent;

                self.accent_speeds[idx] = formation_speed * rng.random_range(1.3, 2.0);
                self.accent_phases[idx] = rng.random_range(0.0, 2.0 * std.math.pi);
                self.accent_breath_speeds[idx] = rng.random_range(0.06, 0.15);
                self.accent_base_alphas[idx] = alpha;
            }
        }
        return self;
    }

    /// Near-stationary drift with left-edge wraparound, a faint breath, and a
    /// slow vertical heave — the standing-wave signature.
    pub fn update(self: *Self, elapsed: f32, w: f32, h: f32) void {
        _ = h;
        for (0..LENS_COUNT) |i| {
            const lens = self.lenses[i];
            const wave = 0.5 + 0.5 * @sin(elapsed * self.breath_speeds[i] + self.phases[i]);
            lens.set_alpha_scale(self.base_alphas[i] * (0.88 + 0.12 * wave));

            const size = lens.get_size();
            var x = lens.pos_x() + self.speeds[i];
            if (x - size > w) x = -size;
            const y = self.base_ys[i] + self.float_amps[i] * @sin(elapsed * self.float_speeds[i] + self.phases[i]);
            lens.set_pos(x, y);
        }
        for (0..ACCENT_COUNT) |i| {
            const accent = self.accents[i];
            const wave = 0.5 + 0.5 * @sin(elapsed * self.accent_breath_speeds[i] + self.accent_phases[i]);
            // Wider breath than the lenses — wispier material, less stable air.
            accent.set_alpha_scale(self.accent_base_alphas[i] * (0.85 + 0.15 * wave));

            const size = accent.get_size();
            var x = accent.pos_x() + self.accent_speeds[i];
            if (x - size > w) x = -size;
            accent.set_pos(x, accent.pos_y());
        }
    }

    /// Kill all lenses and accent clouds (pool compaction reclaims the slots).
    pub fn clear(self: *Self) void {
        for (0..LENS_COUNT) |i| {
            self.lenses[i].set_alive(false);
        }
        for (0..ACCENT_COUNT) |i| {
            self.accents[i].set_alive(false);
        }
    }
};
