const business = @import("core/business.zig");
const Vec2 = business.Vec2;
const particle = @import("Particle.zig");
const random = @import("random.zig");

const MAX_HEADS: usize = 60;
const CLICK_COOLDOWN_FRAMES: u32 = 12;
const METEOR_SIZE: f32 = 8.0;
const TRAIL_SIZE: f32 = 16.0;
const TRAIL_LIFESPAN: f32 = 60.0;
const METEOR_SPEED: f32 = 8.0;
const FADE_MARGIN: f32 = 100.0;

const MeteorHead = struct {
    particle: *particle.Particle,
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

    /// Spawn meteor heads at positions randomly picked from `spawn_positions`,
    /// all flying parallel in the direction from `ref_x, ref_y` toward the click target.
    pub fn falling(self: *MeteorSystem, x: f32, y: f32, ref_x: f32, ref_y: f32, spawn_positions: []const Vec2) void {
        if (self.cooldown > 0) return;
        if (spawn_positions.len == 0) return;
        self.cooldown = CLICK_COOLDOWN_FRAMES;

        const dpr = self.dpr;

        // Single direction vector for all meteors (parallel flight).
        const dx = x - ref_x;
        const dy = y - ref_y;
        const len = @sqrt(dx * dx + dy * dy);
        const base_vx: f32 = if (len < 1.0) 0.0 else dx / len * METEOR_SPEED * dpr;
        const base_vy: f32 = if (len < 1.0) METEOR_SPEED * dpr else dy / len * METEOR_SPEED * dpr;

        const count: usize = 20;

        self.compact();
        const need = (self.head_count + count) -| MAX_HEADS;
        if (need > 0) {
            var freed: usize = 0;
            var j: usize = 0;
            while (j < self.head_count and freed < need) : (j += 1) {
                if (!self.heads[j].particle.immortal) {
                    self.heads[j].particle.alive = false;
                    freed += 1;
                }
            }
            self.compact();
        }

        var i: usize = 0;
        while (i < count) : (i += 1) {
            if (self.head_count >= MAX_HEADS) break;

            const idx = random.randomIndex(spawn_positions.len);
            const sp = spawn_positions[idx];
            const sx = sp.x + random.randomRange(-4.0, 4.0) * dpr;
            const sy = sp.y + random.randomRange(-4.0, 4.0) * dpr;

            const p = particle.allocParticle(Vec2{ .x = sx, .y = sy }, 0, .{
                .immortal = true,
                .meteor = true,
                .size = METEOR_SIZE * dpr,
            });
            const speed_var = random.randomRange(0.7, 1.3);
            p.vel = Vec2{ .x = base_vx * speed_var, .y = base_vy * speed_var };

            self.heads[self.head_count] = MeteorHead{ .particle = p };
            self.head_count += 1;
        }
    }

    pub fn update(self: *MeteorSystem) void {
        const dpr = self.dpr;
        const fade_zone = FADE_MARGIN * dpr;

        var i: usize = 0;
        while (i < self.head_count) : (i += 1) {
            const p = self.heads[i].particle;
            if (!p.alive) continue;

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
                p.alive = false;
                continue;
            }

            var head_fade: f32 = 1.0;
            if (min_dist < fade_zone) {
                head_fade = min_dist / fade_zone;
                if (head_fade < 0.03) {
                    p.alive = false;
                    continue;
                }
                p.immortal = false;
                p.lifespan = head_fade * particle.MAX_LIFESPAN;
                p.size = METEOR_SIZE * dpr * head_fade;
            }

            const trail = particle.allocParticle(Vec2{ .x = trail_x, .y = trail_y }, 0, .{
                .size = TRAIL_SIZE * dpr,
            });
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
        self.compact();
    }

    fn compact(self: *MeteorSystem) void {
        var write: usize = 0;
        var read: usize = 0;
        while (read < self.head_count) : (read += 1) {
            if (self.heads[read].particle.alive) {
                if (write != read) {
                    self.heads[write] = self.heads[read];
                }
                write += 1;
            }
        }
        self.head_count = write;
    }
};
