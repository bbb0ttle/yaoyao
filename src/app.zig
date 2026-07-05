const std = @import("std");
const business = @import("core/business.zig");
const Rgba = business.Rgba;
const Vec2 = business.Vec2;

pub const Canvas = struct {
    buf: []u8,
    width: u32,
    height: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Canvas {
        return Canvas{
            .buf = &[_]u8{},
            .width = 800,
            .height = 600,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Canvas) void {
        if (self.buf.len != 0) {
            self.allocator.free(self.buf);
            self.buf = &[_]u8{};
        }
    }

    pub fn resize(self: *Canvas, new_w: u32, new_h: u32) !void {
        const fb = FrameBuffer{ .buf = self.buf, .width = self.width, .height = self.height };
        const new_fb = try fb.resize(new_w, new_h, self.allocator);
        if (self.buf.len != 0) self.allocator.free(self.buf);
        self.buf = new_fb.buf;
        self.width = new_fb.width;
        self.height = new_fb.height;
    }

    pub fn frameBuffer(self: *const Canvas) FrameBuffer {
        return FrameBuffer{ .buf = self.buf, .width = self.width, .height = self.height };
    }
};

pub const FrameBuffer = struct {
    buf: []u8,
    width: u32,
    height: u32,

    pub fn setPixel(self: FrameBuffer, x: i32, y: i32, color: Rgba) void {
        if (x < 0 or x >= @as(i32, @intCast(self.width))) return;
        if (y < 0 or y >= @as(i32, @intCast(self.height))) return;
        const idx = (@as(usize, @intCast(y)) * @as(usize, self.width) + @as(usize, @intCast(x))) * 4;
        self.buf[idx] = color.r;
        self.buf[idx + 1] = color.g;
        self.buf[idx + 2] = color.b;
        self.buf[idx + 3] = color.a;
    }

    pub fn setPixelAlpha(self: FrameBuffer, x: i32, y: i32, color: Rgba) void {
        if (x < 0 or x >= @as(i32, @intCast(self.width))) return;
        if (y < 0 or y >= @as(i32, @intCast(self.height))) return;
        if (color.a == 0) return;
        if (color.a == 255) {
            self.setPixel(x, y, color);
            return;
        }
        const idx = (@as(usize, @intCast(y)) * @as(usize, self.width) + @as(usize, @intCast(x))) * 4;
        const src_a = @as(u32, color.a);
        const inv_a: u32 = 255 - src_a;
        self.buf[idx] = @as(u8, @intCast((@as(u32, color.r) * src_a + @as(u32, self.buf[idx]) * inv_a) / 255));
        self.buf[idx + 1] = @as(u8, @intCast((@as(u32, color.g) * src_a + @as(u32, self.buf[idx + 1]) * inv_a) / 255));
        self.buf[idx + 2] = @as(u8, @intCast((@as(u32, color.b) * src_a + @as(u32, self.buf[idx + 2]) * inv_a) / 255));
        self.buf[idx + 3] = 255;
    }

    pub fn clear(self: FrameBuffer, color: Rgba) void {
        var i: usize = 0;
        while (i < self.buf.len) : (i += 4) {
            self.buf[i + 0] = color.r;
            self.buf[i + 1] = color.g;
            self.buf[i + 2] = color.b;
            self.buf[i + 3] = color.a;
        }
    }

    pub fn resize(self: FrameBuffer, new_w: u32, new_h: u32, allocator: std.mem.Allocator) !FrameBuffer {
        const new_len: usize = @as(usize, new_w) * @as(usize, new_h) * 4;
        if (new_len == 0) return FrameBuffer{ .buf = &[_]u8{}, .width = new_w, .height = new_h };

        const new_buf = try allocator.alloc(u8, new_len);
        // fill with background color so new areas are never white
        var i: usize = 0;
        while (i < new_len) : (i += 4) {
            new_buf[i + 0] = Rgba.heart_bg.r;
            new_buf[i + 1] = Rgba.heart_bg.g;
            new_buf[i + 2] = Rgba.heart_bg.b;
            new_buf[i + 3] = Rgba.heart_bg.a;
        }
        if (self.buf.len != 0) {
            const copy_w: u32 = if (new_w < self.width) new_w else self.width;
            const copy_h: u32 = if (new_h < self.height) new_h else self.height;
            var y: u32 = 0;
            while (y < copy_h) : (y += 1) {
                const src_start: usize = @as(usize, y) * @as(usize, self.width) * 4;
                const dst_start: usize = @as(usize, y) * @as(usize, new_w) * 4;
                const row_bytes: usize = @as(usize, copy_w) * 4;
                @memcpy(new_buf[dst_start..][0..row_bytes], self.buf[src_start..][0..row_bytes]);
            }
        }
        return FrameBuffer{ .buf = new_buf, .width = new_w, .height = new_h };
    }

    pub fn fillTriangle(self: FrameBuffer, x0: i32, y0: i32, x1: i32, y1: i32, x2: i32, y2: i32, color: Rgba) void {
        const v = business.sortVerticesByY(.{ x0, y0 }, .{ x1, y1 }, .{ x2, y2 });
        const top_y = v[0][1];
        const mid_y = v[1][1];
        const bot_y = v[2][1];
        if (bot_y == top_y) return;

        var y = top_y;
        while (y <= bot_y) : (y += 1) {
            const t2: f32 = if (bot_y != top_y) @as(f32, @floatFromInt(y - top_y)) / @as(f32, @floatFromInt(bot_y - top_y)) else 0;
            const x_left = @as(i32, @intFromFloat(@as(f32, @floatFromInt(v[0][0])) + t2 * @as(f32, @floatFromInt(v[2][0] - v[0][0]))));
            const x_right: i32 = if (y <= mid_y) blk: {
                const t1: f32 = if (mid_y != top_y) @as(f32, @floatFromInt(y - top_y)) / @as(f32, @floatFromInt(mid_y - top_y)) else 0;
                break :blk @as(i32, @intFromFloat(@as(f32, @floatFromInt(v[0][0])) + t1 * @as(f32, @floatFromInt(v[1][0] - v[0][0]))));
            } else blk: {
                const t3: f32 = if (bot_y != mid_y) @as(f32, @floatFromInt(y - mid_y)) / @as(f32, @floatFromInt(bot_y - mid_y)) else 0;
                break :blk @as(i32, @intFromFloat(@as(f32, @floatFromInt(v[1][0])) + t3 * @as(f32, @floatFromInt(v[2][0] - v[1][0]))));
            };
            const lx = if (x_left < x_right) x_left else x_right;
            const rx = if (x_left > x_right) x_left else x_right;
            var x = lx;
            while (x <= rx) : (x += 1) {
                self.setPixel(x, y, color);
            }
        }
    }

    pub fn fillPolygon(self: FrameBuffer, vertices: []const [2]i32, color: Rgba) void {
        if (vertices.len < 3) return;

        var min_y = vertices[0][1];
        var max_y = vertices[0][1];
        for (vertices) |v| {
            if (v[1] < min_y) min_y = v[1];
            if (v[1] > max_y) max_y = v[1];
        }

        var intersections: [64]f32 = undefined;
        var y = min_y;
        while (y <= max_y) : (y += 1) {
            const yf: f32 = @floatFromInt(y);
            var count: usize = 0;
            var i: usize = 0;
            while (i < vertices.len) : (i += 1) {
                const j = (i + 1) % vertices.len;
                const v0y: f32 = @floatFromInt(vertices[i][1]);
                const v1y: f32 = @floatFromInt(vertices[j][1]);
                if ((v0y <= yf and v1y > yf) or (v1y <= yf and v0y > yf)) {
                    const v0x: f32 = @floatFromInt(vertices[i][0]);
                    const v1x: f32 = @floatFromInt(vertices[j][0]);
                    const t: f32 = (yf - v0y) / (v1y - v0y);
                    const x = v0x + t * (v1x - v0x);
                    if (count < 64) {
                        intersections[count] = x;
                        count += 1;
                    }
                }
            }

            var a: usize = 0;
            while (a < count) : (a += 1) {
                var b: usize = a + 1;
                while (b < count) : (b += 1) {
                    if (intersections[a] > intersections[b]) {
                        const tmp = intersections[a];
                        intersections[a] = intersections[b];
                        intersections[b] = tmp;
                    }
                }
            }

            var k: usize = 0;
            while (k + 1 < count) : (k += 2) {
                const xl: f32 = intersections[k];
                const xr: f32 = intersections[k + 1];
                const ixl: i32 = @intFromFloat(xl);
                const ixr: i32 = @intFromFloat(xr);

                if (ixl == ixr) {
                    const cover = @min(1.0, @max(0.0, xr - xl));
                    if (cover > 0.0) {
                        var aa = color;
                        aa.a = @intFromFloat(@as(f32, @floatFromInt(color.a)) * cover);
                        self.setPixelAlpha(ixl, y, aa);
                    }
                } else {
                    // left edge pixel
                    var aa = color;
                    aa.a = @intFromFloat(@as(f32, @floatFromInt(color.a)) * @min(1.0, @max(0.0, @as(f32, @floatFromInt(ixl + 1)) - xl)));
                    self.setPixelAlpha(ixl, y, aa);

                    // interior pixels (fully covered)
                    var x = ixl + 1;
                    while (x < ixr) : (x += 1) {
                        self.setPixelAlpha(x, y, color);
                    }

                    // right edge pixel
                    var aa2 = color;
                    aa2.a = @intFromFloat(@as(f32, @floatFromInt(color.a)) * @min(1.0, @max(0.0, xr - @as(f32, @floatFromInt(ixr)))));
                    self.setPixelAlpha(ixr, y, aa2);
                }
            }
        }
    }

    pub fn drawHeartParticle(self: FrameBuffer, cx: i32, cy: i32, size: f32, fill: Rgba) void {
        const s = size;
        const N: usize = 32;
        var points: [N][2]i32 = undefined;

        // Two cubic bezier curves forming a heart shape:
        // Curve 1 (left):  P0=(0,0), CP1=(-s/2,-s/2), CP2=(-s,s/3), P3=(0,s)
        // Curve 2 (right): P0=(0,s), CP1=(s,s/3),    CP2=(s/2,-s/2), P3=(0,0)
        var pi: usize = 0;
        while (pi < N) : (pi += 1) {
            const t: f32 = @as(f32, @floatFromInt(pi)) / @as(f32, @floatFromInt(N));
            const px: f32, const py: f32 = if (t < 0.5) blk: {
                const t2 = t * 2.0;
                const u = 1.0 - t2;
                const uu = u * u;
                const tt = t2 * t2;
                // 3*uu*t2*(-s/2) + 3*u*tt*(-s)
                const x0 = -1.5 * s * uu * t2 - 3.0 * s * u * tt;
                // 3*uu*t2*(-s/2) + 3*u*tt*(s/3) + tt*t2*s
                const y0 = -1.5 * s * uu * t2 + s * u * tt + s * tt * t2;
                break :blk .{ x0, y0 };
            } else blk: {
                const t2 = (t - 0.5) * 2.0;
                const u = 1.0 - t2;
                const uu = u * u;
                const tt = t2 * t2;
                // 3*uu*t2*s + 3*u*tt*(s/2)
                const x1 = 3.0 * s * uu * t2 + 1.5 * s * u * tt;
                // u*uu*s + 3*uu*t2*(s/3) + 3*u*tt*(-s/2)
                const y1 = s * u * uu + s * uu * t2 - 1.5 * s * u * tt;
                break :blk .{ x1, y1 };
            };
            points[pi] = .{ cx + @as(i32, @intFromFloat(px)), cy + @as(i32, @intFromFloat(py)) };
        }

        self.fillPolygon(points[0..], fill);
    }

    pub fn drawChar(self: FrameBuffer, x: i32, y: i32, ch: u8, char_scale: u32, color: Rgba) void {
        const idx = business.charIndex(ch);
        if (idx >= business.FONT_3X5.len) return;

        const glyph = business.FONT_3X5[idx];
        var row: usize = 0;
        while (row < 5) : (row += 1) {
            const bits = glyph[row];
            var col: usize = 0;
            while (col < 3) : (col += 1) {
                if ((bits >> @as(u3, @intCast(2 - col))) & 1 == 1) {
                    var dy: u32 = 0;
                    while (dy < char_scale) : (dy += 1) {
                        var dx: u32 = 0;
                        while (dx < char_scale) : (dx += 1) {
                            self.setPixel(
                                x + @as(i32, @intCast(col * char_scale)) + @as(i32, @intCast(dx)),
                                y + @as(i32, @intCast(row * char_scale)) + @as(i32, @intCast(dy)),
                                color,
                            );
                        }
                    }
                }
            }
        }
    }

    pub fn drawText(self: FrameBuffer, x: i32, y: i32, text: []const u8, char_scale: u32, color: Rgba) void {
        const char_width: i32 = @as(i32, @intCast(3 * char_scale + char_scale));
        var cx = x;
        for (text) |ch| {
            self.drawChar(cx, y, ch, char_scale, color);
            cx += char_width;
        }
    }
};

// --- Particle System ---

const MAX_LIFESPAN: f32 = 135.0;
const MAX_PARTICLE_SIZE: f32 = 12.0;

pub const ParticleOpts = struct {
    immortal: bool = false,
    floating: bool = false,
    beat: bool = false,
    meteor: bool = false,
    size: f32 = MAX_PARTICLE_SIZE,
};

const Particle = struct {
    pos: Vec2,
    vel: Vec2,
    acc: Vec2,
    lifespan: f32,
    size: f32,
    age: f32,
    birth_sec: f32,
    alive: bool,
    immortal: bool,
    floating: bool,
    beat: bool,
    meteor: bool,

    fn init(pos: Vec2, birth_sec: f32, opts: ParticleOpts) Particle {
        return Particle{
            .pos = pos.copy(),
            .vel = Vec2{ .x = randomRange(-1.0, 1.0), .y = randomRange(-1.0, 0.0) },
            .acc = Vec2{ .x = 0.0, .y = 0.08 },
            .lifespan = MAX_LIFESPAN,
            .size = opts.size,
            .age = 0.0,
            .birth_sec = birth_sec,
            .alive = true,
            .immortal = opts.immortal,
            .floating = opts.floating,
            .beat = opts.beat,
            .meteor = opts.meteor,
        };
    }

    fn update(self: *Particle, elapsed: f32, dpr: f32) void {
        if (!self.alive) return;
        if (self.meteor) return;
        self.age += 0.2;

        if (!self.immortal and !self.floating) {
            self.vel = self.vel.add(self.acc);
            self.lifespan -= 2.0;
        }

        if (self.floating) {
            self.pos.x += @sin(self.age) / 6.0;
            self.pos.y += @cos(self.age) / 6.0;
        } else {
            self.pos = self.pos.add(self.vel);
        }

        if (self.beat) {
            const real_age = elapsed - self.birth_sec;
            self.size = business.breath(real_age, (MAX_PARTICLE_SIZE - 3.0) * dpr, MAX_PARTICLE_SIZE * dpr);
        }

        if (self.lifespan < 0.0) {
            self.alive = false;
        }
    }

    fn isDead(self: Particle) bool {
        return !self.alive;
    }
};

const PARTICLE_POOL_SIZE: usize = 5000;
var particle_pool: [PARTICLE_POOL_SIZE]Particle = undefined;
var particle_pool_len: usize = 0;

fn allocParticle(pos: Vec2, elapsed: f32, opts: ParticleOpts) *Particle {
    if (particle_pool_len >= PARTICLE_POOL_SIZE) {
        var i: usize = 0;
        while (i < PARTICLE_POOL_SIZE) : (i += 1) {
            if (!particle_pool[i].alive) {
                particle_pool[i] = Particle.init(pos, elapsed, opts);
                return &particle_pool[i];
            }
        }
        particle_pool[0] = Particle.init(pos, elapsed, opts);
        return &particle_pool[0];
    }
    particle_pool[particle_pool_len] = Particle.init(pos, elapsed, opts);
    const p = &particle_pool[particle_pool_len];
    particle_pool_len += 1;
    return p;
}

const CONTOUR_COUNT: usize = 30;

const ContourPoint = struct {
    index: f32,
    immortal: *Particle,
};

// --- HeartSystem ---

pub const HeartSystem = struct {
    contour: [CONTOUR_COUNT]ContourPoint,
    float_pair: [2]*Particle,
    birth_sec: f32,
    cx: f32,
    cy: f32,
    canvas_h: f32,
    dpr: f32,

    pub fn init(elapsed: f32, cx: f32, cy: f32, canvas_h: f32, fp_x: f32, fp_y: f32, dpr: f32) HeartSystem {
        particle_pool_len = 0;

        var self = HeartSystem{
            .contour = undefined,
            .float_pair = undefined,
            .birth_sec = elapsed,
            .cx = cx,
            .cy = cy,
            .canvas_h = canvas_h,
            .dpr = dpr,
        };

        const start: f32 = 0.0;
        const end: f32 = 2.0 * std.math.pi;
        const step: f32 = (end - start) / @as(f32, @floatFromInt(CONTOUR_COUNT));
        const hscale: f32 = 50.0 * dpr;

        var i: usize = 0;
        var t: f32 = start;
        while (i < CONTOUR_COUNT) : ({
            i += 1;
            t += step;
        }) {
            const hp = business.createHeartPos(t);
            const pos = Vec2{ .x = hp.x * hscale + hscale + cx, .y = hp.y * hscale + hscale + cy };
            self.contour[i] = ContourPoint{
                .index = t,
                .immortal = allocParticle(pos, elapsed, .{ .immortal = true, .size = MAX_PARTICLE_SIZE * dpr }),
            };
        }

        self.float_pair[0] = allocParticle(Vec2{ .x = fp_x, .y = fp_y }, elapsed, .{
            .immortal = true,
            .floating = true,
            .beat = true,
            .size = MAX_PARTICLE_SIZE * dpr,
        });
        self.float_pair[1] = allocParticle(Vec2{ .x = fp_x + 7.0 * dpr, .y = fp_y - 2.0 * dpr }, elapsed, .{
            .immortal = true,
            .floating = true,
            .beat = true,
            .size = MAX_PARTICLE_SIZE * dpr,
        });

        return self;
    }

    pub fn update(self: *HeartSystem, elapsed: f32) void {
        const dpr = self.dpr;
        const scale_val = business.breath(elapsed - self.birth_sec, 50.0 * dpr, 60.0 * dpr);
        const size_val = business.breath(elapsed - self.birth_sec, 10.0 * dpr, 15.0 * dpr);

        for (&self.contour) |*cp| {
            const hp = business.createHeartPos(cp.index);
            cp.immortal.pos.x = hp.x * scale_val + 50.0 * dpr + self.cx;
            cp.immortal.pos.y = hp.y * scale_val + 50.0 * dpr + self.cy - 5.0 * dpr;
            cp.immortal.size = size_val;

            _ = allocParticle(cp.immortal.pos.copy(), elapsed, .{ .size = MAX_PARTICLE_SIZE * dpr });
        }

        var i: usize = 0;
        while (i < particle_pool_len) : (i += 1) {
            var p = &particle_pool[i];
            if (p.alive) {
                p.update(elapsed, dpr);
            }
        }
    }

    pub fn render(self: HeartSystem, fb: FrameBuffer, elapsed: f32, t: f32) void {
        _ = elapsed;
        const stroke_width: f32 = 2.0 * self.dpr;
        var i: usize = 0;
        while (i < particle_pool_len) : (i += 1) {
            const p = &particle_pool[i];
            if (!p.alive) continue;

            const max_alpha: f32 = if (p.immortal) 255.0 else business.scale(p.lifespan, MAX_LIFESPAN, 200.0);

            const px: i32 = @as(i32, @intFromFloat(p.pos.x));
            const py: i32 = @as(i32, @intFromFloat(p.pos.y));
            const display_size: f32 = business.scale(p.lifespan, MAX_LIFESPAN, p.size);

            var stroke_color = Rgba.heart_stroke;
            stroke_color.a = @intFromFloat(@min(255.0, p.lifespan) * t);
            fb.drawHeartParticle(px, py, display_size + stroke_width, stroke_color);

            var fill = Rgba.heart_fill;
            fill.a = @intFromFloat(max_alpha * t);
            fb.drawHeartParticle(px, py, display_size, fill);
        }
    }
};

// --- MeteorSystem ---

const MAX_HEADS: usize = 15;
const METEOR_SIZE: f32 = 8.0;
const TRAIL_SIZE: f32 = 12.0;
const TRAIL_LIFESPAN: f32 = 50.0;
const METEOR_SPEED: f32 = 6.0;
const FADE_MARGIN: f32 = 100.0;

const MeteorHead = struct {
    particle: *Particle,
};

pub const MeteorSystem = struct {
    heads: [MAX_HEADS]MeteorHead,
    head_count: usize,
    vel_x: f32,
    vel_y: f32,
    canvas_w: f32,
    canvas_h: f32,
    dpr: f32,

    pub fn init(canvas_w: f32, canvas_h: f32, dpr: f32) MeteorSystem {
        return MeteorSystem{
            .heads = undefined,
            .head_count = 0,
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

        self.vel_x = dx / len * METEOR_SPEED * dpr;
        self.vel_y = dy / len * METEOR_SPEED * dpr;

        const count: usize = 12;
        const spread_range: f32 = cw * 0.5;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            if (self.head_count >= MAX_HEADS) break;

            const sx: f32 = cw - margin - randomRange(0, spread_range);
            const sy: f32 = margin + randomRange(0, spread_range * 0.4);

            const p = allocParticle(Vec2{ .x = sx, .y = sy }, 0, .{
                .immortal = true,
                .meteor = true,
                .size = METEOR_SIZE * dpr,
            });
            const speed_var = randomRange(0.7, 1.3);
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

            // fade out when approaching any screen edge
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
                p.lifespan = head_fade * MAX_LIFESPAN;
                p.size = METEOR_SIZE * dpr * head_fade;
            }

            // spawn trail at previous position, lifespan capped by head's fade ratio
            const trail = allocParticle(Vec2{ .x = trail_x, .y = trail_y }, 0, .{
                .size = TRAIL_SIZE * dpr,
            });
            trail.vel = Vec2{ .x = 0, .y = 0 };
            trail.acc = Vec2{ .x = 0, .y = 0 };

            const tdl = trail_x;
            const tdr = self.canvas_w - trail_x;
            const tdt = trail_y;
            const tdb = self.canvas_h - trail_y;
            const trail_min = @min(@min(tdl, tdr), @min(tdt, tdb));
            const trail_edge_fade: f32 = if (trail_min <= 0) 0.0
                else if (trail_min < fade_zone) trail_min / fade_zone
                else 1.0;
            trail.lifespan = @min(head_fade, trail_edge_fade) * TRAIL_LIFESPAN;
        }

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

// Simple deterministic pseudo-random for particle velocity initialization.
var rng_state: u64 = 12345;
fn randomRange(lo: f32, hi: f32) f32 {
    rng_state = rng_state *% 6364136223846793005 +% 1442695040888963407;
    const r = @as(f32, @floatFromInt((rng_state >> 33) & 0x7FFFFFFF)) / @as(f32, @floatFromInt(0x7FFFFFFF));
    return lo + (hi - lo) * r;
}
