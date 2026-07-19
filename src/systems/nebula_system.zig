//! Nebula background: large diffuse blobs drifting and breathing softly.
//!
//! Blobs render through the instanced pipeline as gaussian-falloff puffs
//! (shader shape 3). Bigger blobs are dimmer and slower, reading as distant
//! layers; smaller ones are brighter and drift faster — a sense of depth.

const std = @import("std");
const log = std.log.scoped(.nebula);

const Vec2 = @import("../core/types.zig").Vec2;
const Particle = @import("../particles/particle.zig").Particle;
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const Rng = @import("../random.zig").Rng;

const MAX_BLOBS: usize = 24;
const MIN_BLOBS: f32 = 10.0;
const AREA_PER_BLOB: f32 = 150000.0;

/// Fixed-size nebula layer; zero allocation after init.
pub const NebulaSystem = struct {
    const Self = @This();

    blobs: [MAX_BLOBS]*Particle,
    drifts: [MAX_BLOBS]Vec2,
    phases: [MAX_BLOBS]f32,
    speeds: [MAX_BLOBS]f32,
    base_alphas: [MAX_BLOBS]f32,
    blob_count: usize,

    pub fn init(pool: *ParticlePool, rng: *Rng, w: f32, h: f32, dpr: f32, elapsed: f32) Self {
        var self = Self{
            .blobs = undefined,
            .drifts = undefined,
            .phases = undefined,
            .speeds = undefined,
            .base_alphas = undefined,
            .blob_count = 0,
        };

        const want: usize = @intFromFloat(std.math.clamp(w * h / AREA_PER_BLOB, MIN_BLOBS, @as(f32, @floatFromInt(MAX_BLOBS))));
        while (self.blob_count < want) {
            const i = self.blob_count;
            const size = rng.random_range(60.0, 200.0) * dpr;
            const blob = pool.alloc_particle(
                Vec2{ .x = rng.random_range(0.0, w), .y = rng.random_range(0.0, h) },
                elapsed,
                .{ .immortal = true, .blob = true, .size = size },
                rng,
            );
            blob.set_vel(0, 0);
            blob.set_acc(0, 0);
            self.blobs[i] = blob;

            // Depth: big blobs sit far (dim, slow), small ones near (bright, fast).
            const nearness = 1.0 - (size / dpr - 60.0) / 140.0;
            const angle = rng.random_range(0.0, 2.0 * std.math.pi);
            const speed = rng.random_range(0.04, 0.12) * dpr * (0.5 + nearness);
            self.drifts[i] = Vec2{ .x = @cos(angle) * speed, .y = @sin(angle) * speed };
            self.phases[i] = rng.random_range(0.0, 2.0 * std.math.pi);
            self.speeds[i] = rng.random_range(0.4, 0.8);
            self.base_alphas[i] = rng.random_range(0.10, 0.20) * (0.7 + 0.6 * nearness);
            self.blob_count += 1;
        }
        return self;
    }

    /// Breathe each blob's alpha and drift it, bouncing softly off the edges.
    pub fn update(self: *Self, elapsed: f32, w: f32, h: f32) void {
        var i: usize = 0;
        while (i < self.blob_count) : (i += 1) {
            const blob = self.blobs[i];
            const wave = 0.5 + 0.5 * @sin(elapsed * self.speeds[i] + self.phases[i]);
            blob.set_alpha_scale(self.base_alphas[i] * (0.6 + 0.4 * wave));

            const margin = blob.get_size() * 0.5;
            const next_x = blob.pos_x() + self.drifts[i].x;
            const next_y = blob.pos_y() + self.drifts[i].y;
            if (next_x < -margin or next_x > w + margin) self.drifts[i].x = -self.drifts[i].x;
            if (next_y < -margin or next_y > h + margin) self.drifts[i].y = -self.drifts[i].y;
            blob.translate(self.drifts[i].x, self.drifts[i].y);
        }
    }

    /// Kill all blobs (pool compaction reclaims the slots).
    pub fn clear(self: *Self) void {
        var i: usize = 0;
        while (i < self.blob_count) : (i += 1) {
            self.blobs[i].set_alive(false);
        }
        self.blob_count = 0;
    }
};
