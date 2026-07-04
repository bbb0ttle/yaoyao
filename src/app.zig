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

        var intersections: [64]i32 = undefined;
        var y = min_y;
        while (y <= max_y) : (y += 1) {
            var count: usize = 0;
            var i: usize = 0;
            while (i < vertices.len) : (i += 1) {
                const j = (i + 1) % vertices.len;
                const v0 = vertices[i];
                const v1 = vertices[j];
                if ((v0[1] <= y and v1[1] > y) or (v1[1] <= y and v0[1] > y)) {
                    const t: f32 = @as(f32, @floatFromInt(y - v0[1])) / @as(f32, @floatFromInt(v1[1] - v0[1]));
                    const x = @as(i32, @intFromFloat(@as(f32, @floatFromInt(v0[0])) + t * @as(f32, @floatFromInt(v1[0] - v0[0]))));
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
                var x = intersections[k];
                const end = intersections[k + 1];
                while (x <= end) : (x += 1) {
                    self.setPixelAlpha(x, y, color);
                }
            }
        }
    }

    pub fn drawHeartParticle(self: FrameBuffer, cx: i32, cy: i32, size: f32, fill: Rgba) void {
        const s = size;
        const N: usize = 16;
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

const MAX_LIFESPAN: f32 = 80.0;
const MAX_PARTICLE_SIZE: f32 = 12.0;

pub const ParticleOpts = struct {
    immortal: bool = false,
    floating: bool = false,
    beat: bool = false,
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
        };
    }

    fn update(self: *Particle, elapsed: f32, dpr: f32) void {
        if (!self.alive) return;
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

const PARTICLE_POOL_SIZE: usize = 800;
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

    pub fn init(elapsed: f32, cx: f32, cy: f32, canvas_h: f32, dpr: f32) HeartSystem {
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

        self.float_pair[0] = allocParticle(Vec2{ .x = cx - 7.0 * dpr, .y = canvas_h - 80.0 * dpr }, elapsed, .{
            .immortal = true,
            .floating = true,
            .beat = true,
            .size = MAX_PARTICLE_SIZE * dpr,
        });
        self.float_pair[1] = allocParticle(Vec2{ .x = cx, .y = canvas_h - 82.0 * dpr }, elapsed, .{
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

    pub fn render(self: HeartSystem, fb: FrameBuffer, elapsed: f32) void {
        _ = elapsed;
        const stroke_width: f32 = 2.0 * self.dpr;
        var i: usize = 0;
        while (i < particle_pool_len) : (i += 1) {
            const p = &particle_pool[i];
            if (!p.alive) continue;

            const alpha: u8 = if (p.immortal) 255 else @as(u8, @intCast(@max(0, @min(255, @as(i32, @intFromFloat(business.scale(p.lifespan, MAX_LIFESPAN, 200.0)))))));

            const px: i32 = @as(i32, @intFromFloat(p.pos.x));
            const py: i32 = @as(i32, @intFromFloat(p.pos.y));
            const display_size: f32 = business.scale(p.lifespan, MAX_LIFESPAN, p.size);

            // stroke: heart_stroke color with lifespan-based alpha
            var stroke_color = Rgba.heart_stroke;
            stroke_color.a = @as(u8, @intCast(@max(0, @min(255, @as(i32, @intFromFloat(p.lifespan))))));
            fb.drawHeartParticle(px, py, display_size + stroke_width, stroke_color);

            // fill
            var fill = Rgba.heart_fill;
            fill.a = alpha;
            fb.drawHeartParticle(px, py, display_size, fill);
        }
    }
};

// Simple deterministic pseudo-random for particle velocity initialization.
var rng_state: u64 = 12345;
fn randomRange(lo: f32, hi: f32) f32 {
    rng_state = rng_state *% 6364136223846793005 +% 1442695040888963407;
    const r = @as(f32, @floatFromInt((rng_state >> 33) & 0x7FFFFFFF)) / @as(f32, @floatFromInt(0x7FFFFFFF));
    return lo + (hi - lo) * r;
}
