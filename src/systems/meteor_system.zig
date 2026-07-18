//! Meteor shower effect with edge-fade, trail particles, and head compaction.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.meteor_system);

const Vec2 = @import("../core/types.zig").Vec2;
const Particle = @import("../particles/particle.zig").Particle;
const ParticleOpts = @import("../particles/particle.zig").ParticleOpts;
const MAX_LIFESPAN = @import("../particles/particle.zig").MAX_LIFESPAN;
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const Rng = @import("../random.zig").Rng;

const MAX_HEADS: usize = 60;
const CLICK_COOLDOWN_FRAMES: u32 = 12;
pub const METEOR_SIZE: f32 = 8.0;
pub const TRAIL_SIZE: f32 = 16.0;
pub const TRAIL_LIFESPAN: f32 = 60.0;
pub const METEOR_SPEED: f32 = 8.0;
const FADE_MARGIN: f32 = 100.0;

const MeteorHead = struct {
    particle: *Particle,
};

/// Meteor shower system with head compaction, edge fading, and trail particles.
pub const MeteorSystem = struct {
    const Self = @This();

    heads: [MAX_HEADS]MeteorHead,
    head_count: usize,
    cooldown: u32,
    canvas_w: f32,
    canvas_h: f32,
    dpr: f32,

    pub fn init(canvas_w: f32, canvas_h: f32, dpr: f32) Self {
        return Self{
            .heads = undefined,
            .head_count = 0,
            .cooldown = 0,
            .canvas_w = canvas_w,
            .canvas_h = canvas_h,
            .dpr = dpr,
        };
    }

    /// Spawn a meteor shower from `spawn_positions`, all heads travelling
    /// parallel along (dir_x, dir_y).
    pub fn falling(
        self: *Self,
        pool: *ParticlePool,
        rng: *Rng,
        dir_x: f32,
        dir_y: f32,
        spawn_positions: []const Vec2,
        force: bool,
    ) void {
        if (!force and self.cooldown > 0) return;
        if (spawn_positions.len == 0) return;
        self.cooldown = CLICK_COOLDOWN_FRAMES;

        const dpr = self.dpr;

        const len = @sqrt(dir_x * dir_x + dir_y * dir_y);
        const base_vx: f32 = if (len < 1.0) 0.0 else dir_x / len * METEOR_SPEED * dpr;
        const base_vy: f32 = if (len < 1.0) METEOR_SPEED * dpr else dir_y / len * METEOR_SPEED * dpr;

        const count: usize = 20;

        self.compact();
        const need = (self.head_count + count) -| MAX_HEADS;
        if (need > 0) {
            var freed: usize = 0;
            var j: usize = 0;
            while (j < self.head_count and freed < need) : (j += 1) {
                if (!self.heads[j].particle.is_immortal()) {
                    self.heads[j].particle.set_alive(false);
                    freed += 1;
                }
            }
            self.compact();
        }

        var i: usize = 0;
        while (i < count) : (i += 1) {
            if (self.head_count >= MAX_HEADS) break;

            const idx = rng.random_index(spawn_positions.len);
            const sp = spawn_positions[idx];
            const sx = sp.x + rng.random_range(-4.0, 4.0) * dpr;
            const sy = sp.y + rng.random_range(-4.0, 4.0) * dpr;

            const p = pool.alloc_particle(Vec2{ .x = sx, .y = sy }, 0, .{
                .immortal = true,
                .meteor = true,
                .size = METEOR_SIZE * dpr,
            }, rng);
            const speed_var = rng.random_range(0.7, 1.3);
            p.set_vel(base_vx * speed_var, base_vy * speed_var);

            self.heads[self.head_count] = MeteorHead{ .particle = p };
            self.head_count += 1;
        }
    }

    pub fn update(self: *Self, pool: *ParticlePool, rng: *Rng) void {
        const dpr = self.dpr;
        const fade_zone = FADE_MARGIN * dpr;

        var i: usize = 0;
        while (i < self.head_count) : (i += 1) {
            const p = self.heads[i].particle;
            if (!p.is_alive()) continue;

            const trail_x = p.pos_x();
            const trail_y = p.pos_y();
            p.translate_by_vel();

            const dist_left = p.pos_x();
            const dist_right = self.canvas_w - p.pos_x();
            const dist_top = p.pos_y();
            const dist_bottom = self.canvas_h - p.pos_y();
            const min_dist = @min(@min(dist_left, dist_right), @min(dist_top, dist_bottom));

            if (min_dist <= 0) {
                p.set_alive(false);
                continue;
            }

            var head_fade: f32 = 1.0;
            if (min_dist < fade_zone) {
                head_fade = min_dist / fade_zone;
                if (head_fade < 0.03) {
                    p.set_alive(false);
                    continue;
                }
                p.set_immortal(false);
                p.set_lifespan(head_fade * MAX_LIFESPAN);
                p.set_size(METEOR_SIZE * dpr * head_fade);
            }

            const trail = pool.alloc_particle(Vec2{ .x = trail_x, .y = trail_y }, 0, .{
                .size = TRAIL_SIZE * dpr,
            }, rng);
            trail.set_vel(0, 0);
            trail.set_acc(0, 0);

            const tdl = trail_x;
            const tdr = self.canvas_w - trail_x;
            const tdt = trail_y;
            const tdb = self.canvas_h - trail_y;
            const trail_min = @min(@min(tdl, tdr), @min(tdt, tdb));
            const trail_edge_fade: f32 = if (trail_min <= 0) 0.0 else if (trail_min < fade_zone) trail_min / fade_zone else 1.0;
            trail.set_lifespan(@min(head_fade, trail_edge_fade) * TRAIL_LIFESPAN);
        }

        if (self.cooldown > 0) self.cooldown -= 1;
        self.compact();
    }

    fn compact(self: *Self) void {
        var write: usize = 0;
        var read: usize = 0;
        while (read < self.head_count) : (read += 1) {
            if (self.heads[read].particle.is_alive()) {
                if (write != read) {
                    self.heads[write] = self.heads[read];
                }
                write += 1;
            }
        }
        self.head_count = write;
    }
};
