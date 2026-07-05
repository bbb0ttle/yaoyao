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
    vel_x: f32,
    vel_y: f32,
    canvas_w: f32,
    canvas_h: f32,
    dpr: f32,

    pub fn init(canvas_w: f32, canvas_h: f32, dpr: f32) MeteorSystem {
        return MeteorSystem{
            .heads = undefined,
            .head_count = 0,
            .cooldown = 0,
            .vel_x = 0,
            .vel_y = 0,
            .canvas_w = canvas_w,
            .canvas_h = canvas_h,
            .dpr = dpr,
        };
    }

    pub fn on_click(self: *MeteorSystem, x: f32, y: f32) void {
        const dpr = self.dpr;
        const cw = self.canvas_w;
        const margin = FADE_MARGIN * dpr;

        const src_cx = cw - margin;
        const src_cy = margin;
        const dx = x - src_cx;
        const dy = y - src_cy;
        const len = @sqrt(dx * dx + dy * dy);
        if (len < 1.0) return;
        if (self.cooldown > 0) return;
        self.cooldown = CLICK_COOLDOWN_FRAMES;

        self.vel_x = dx / len * METEOR_SPEED * dpr;
        self.vel_y = dy / len * METEOR_SPEED * dpr;

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

        const spread_range: f32 = cw * 0.5;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            if (self.head_count >= MAX_HEADS) break;

            const sx: f32 = cw - margin - random.randomRange(0, spread_range);
            const sy: f32 = margin + random.randomRange(0, spread_range * 0.4);

            const p = particle.allocParticle(Vec2{ .x = sx, .y = sy }, 0, .{
                .immortal = true,
                .meteor = true,
                .size = METEOR_SIZE * dpr,
            });
            const speed_var = random.randomRange(0.7, 1.3);
            p.vel = Vec2{ .x = self.vel_x * speed_var, .y = self.vel_y * speed_var };

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
