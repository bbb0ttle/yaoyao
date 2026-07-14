const Vec2 = @import("../core/types.zig").Vec2;
const Particle = @import("../particles/particle.zig").Particle;
const ParticleOpts = @import("../particles/particle.zig").ParticleOpts;
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const Rng = @import("../random.zig").Rng;

const MAX_HEADS: usize = 60;
const CLICK_COOLDOWN_FRAMES: u32 = 12;
const METEOR_SIZE: f32 = 8.0;
const TRAIL_SIZE: f32 = 16.0;
const TRAIL_LIFESPAN: f32 = 60.0;
const METEOR_SPEED: f32 = 8.0;
const FADE_MARGIN: f32 = 100.0;

const MeteorHead = struct {
    particle: *Particle,
};

pub const MeteorSystem = struct {
    heads: [MAX_HEADS]MeteorHead,
    head_count: usize,
    cooldown: u32,
    canvas_w: f32,
    canvas_h: f32,
    dpr: f32,

    pub fn init(canvas_w: f32, canvas_h: f32, dpr: f32) MeteorSystem {
        return MeteorSystem{
            .heads = undefined,
            .head_count = 0,
            .cooldown = 0,
            .canvas_w = canvas_w,
            .canvas_h = canvas_h,
            .dpr = dpr,
        };
    }

    pub fn falling(
        self: *MeteorSystem,
        pool: *ParticlePool,
        rng: *Rng,
        x: f32,
        y: f32,
        ref_x: f32,
        ref_y: f32,
        spawn_positions: []const Vec2,
    ) void {
        if (self.cooldown > 0) return;
        if (spawn_positions.len == 0) return;
        self.cooldown = CLICK_COOLDOWN_FRAMES;

        const dpr = self.dpr;

        const dx = x - ref_x;
        const dy = y - ref_y;
        const len = @sqrt(dx * dx + dy * dy);
        const base_vx: f32 = if (len < 1.0) 0.0 else dx / len * METEOR_SPEED * dpr;
        const base_vy: f32 = if (len < 1.0) METEOR_SPEED * dpr else dy / len * METEOR_SPEED * dpr;

        const count: usize = 20;

        self._compact();
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
            self._compact();
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
            p.vel = Vec2{ .x = base_vx * speed_var, .y = base_vy * speed_var };

            self.heads[self.head_count] = MeteorHead{ .particle = p };
            self.head_count += 1;
        }
    }

    pub fn update(self: *MeteorSystem, pool: *ParticlePool, rng: *Rng) void {
        const dpr = self.dpr;
        const fade_zone = FADE_MARGIN * dpr;

        var i: usize = 0;
        while (i < self.head_count) : (i += 1) {
            const p = self.heads[i].particle;
            if (!p.is_alive()) continue;

            p.pos.x += p.vel.x;
            p.pos.y += p.vel.y;

            const trail_x = p.pos.x - p.vel.x;
            const trail_y = p.pos.y - p.vel.y;

            const dist_left = p.pos.x;
            const dist_right = self.canvas_w - p.pos.x;
            const dist_top = p.pos.y;
            const dist_bottom = self.canvas_h - p.pos.y;
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
                p.lifespan = head_fade * @import("../particles/particle.zig").MAX_LIFESPAN;
                p.size = METEOR_SIZE * dpr * head_fade;
            }

            const trail = pool.alloc_particle(Vec2{ .x = trail_x, .y = trail_y }, 0, .{
                .size = TRAIL_SIZE * dpr,
            }, rng);
            trail.vel = Vec2{ .x = 0, .y = 0 };
            trail.acc = Vec2{ .x = 0, .y = 0 };

            const tdl = trail_x;
            const tdr = self.canvas_w - trail_x;
            const tdt = trail_y;
            const tdb = self.canvas_h - trail_y;
            const trail_min = @min(@min(tdl, tdr), @min(tdt, tdb));
            const trail_edge_fade: f32 = if (trail_min <= 0) 0.0 else if (trail_min < fade_zone) trail_min / fade_zone else 1.0;
            trail.lifespan = @min(head_fade, trail_edge_fade) * TRAIL_LIFESPAN;
        }

        if (self.cooldown > 0) self.cooldown -= 1;
        self._compact();
    }

    fn _compact(self: *MeteorSystem) void {
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
