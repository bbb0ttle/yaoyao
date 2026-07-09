const std = @import("std");
const business = @import("core/business.zig");
const Rgba = business.Rgba;

const HEART_VERTEX_COUNT: usize = 32;

fn makeHeartUnitVertices() [HEART_VERTEX_COUNT][2]f32 {
    var pts: [HEART_VERTEX_COUNT][2]f32 = undefined;
    var pi: usize = 0;
    while (pi < HEART_VERTEX_COUNT) : (pi += 1) {
        const t: f32 = @as(f32, @floatFromInt(pi)) / @as(f32, @floatFromInt(HEART_VERTEX_COUNT));
        const px: f32, const py: f32 = if (t < 0.5) blk: {
            const t2 = t * 2.0;
            const u = 1.0 - t2;
            const uu = u * u;
            const tt = t2 * t2;
            const x0 = -1.5 * uu * t2 - 3.0 * u * tt;
            const y0 = -1.5 * uu * t2 + u * tt + tt * t2;
            break :blk .{ x0, y0 };
        } else blk: {
            const t2 = (t - 0.5) * 2.0;
            const u = 1.0 - t2;
            const uu = u * u;
            const tt = t2 * t2;
            const x1 = 3.0 * uu * t2 + 1.5 * u * tt;
            const y1 = u * uu + uu * t2 - 1.5 * u * tt;
            break :blk .{ x1, y1 };
        };
        pts[pi] = .{ px, py };
    }
    return pts;
}

const heart_unit_vertices = makeHeartUnitVertices();

pub const FrameBuffer = struct {
    buf: []u8,
    width: u32,
    height: u32,
    bytes_per_row: u32,

    fn pixelOffset(self: FrameBuffer, x: i32, y: i32) usize {
        return @as(usize, @intCast(y)) * self.bytes_per_row + @as(usize, @intCast(x)) * 4;
    }

    pub fn setPixel(self: FrameBuffer, x: i32, y: i32, color: Rgba) void {
        if (x < 0 or x >= @as(i32, @intCast(self.width))) return;
        if (y < 0 or y >= @as(i32, @intCast(self.height))) return;
        const idx = self.pixelOffset(x, y);
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
        const idx = self.pixelOffset(x, y);
        const src_a = @as(u32, color.a);
        const inv_a: u32 = 255 - src_a;
        self.buf[idx] = @as(u8, @intCast((@as(u32, color.r) * src_a + @as(u32, self.buf[idx]) * inv_a) / 255));
        self.buf[idx + 1] = @as(u8, @intCast((@as(u32, color.g) * src_a + @as(u32, self.buf[idx + 1]) * inv_a) / 255));
        self.buf[idx + 2] = @as(u8, @intCast((@as(u32, color.b) * src_a + @as(u32, self.buf[idx + 2]) * inv_a) / 255));
        self.buf[idx + 3] = 255;
    }

    pub fn clear(self: FrameBuffer, color: Rgba) void {
        const word: u32 = (@as(u32, color.r))
            | (@as(u32, color.g) << 8)
            | (@as(u32, color.b) << 16)
            | (@as(u32, color.a) << 24);
        if (self.bytes_per_row == self.width * 4) {
            const word_count = self.buf.len / 4;
            const words = @as([*]u32, @ptrCast(@alignCast(self.buf.ptr)))[0..word_count];
            @memset(words, word);
        } else {
            const line_words: usize = @intCast(self.width);
            var y: u32 = 0;
            while (y < self.height) : (y += 1) {
                const row_start = @as(usize, @intCast(y)) * self.bytes_per_row;
                const words = @as([*]u32, @ptrCast(@alignCast(self.buf.ptr + row_start)))[0..line_words];
                @memset(words, word);
            }
        }
    }

    pub fn resize(self: FrameBuffer, new_w: u32, new_h: u32, allocator: std.mem.Allocator) !FrameBuffer {
        const new_bpr = new_w * 4;
        const new_len: usize = @as(usize, new_w) * @as(usize, new_h) * 4;
        if (new_len == 0) return FrameBuffer{ .buf = &[_]u8{}, .width = new_w, .height = new_h, .bytes_per_row = new_bpr };

        const new_buf = try allocator.alloc(u8, new_len);
        @memset(new_buf, 0);
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
                const src_start: usize = @as(usize, y) * self.bytes_per_row;
                const dst_start: usize = @as(usize, y) * new_bpr;
                const row_bytes: usize = @as(usize, copy_w) * 4;
                @memcpy(new_buf[dst_start..][0..row_bytes], self.buf[src_start..][0..row_bytes]);
            }
        }
        return FrameBuffer{ .buf = new_buf, .width = new_w, .height = new_h, .bytes_per_row = new_bpr };
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

            // insertion sort — faster than bubble sort for small arrays
            var a: usize = 1;
            while (a < count) : (a += 1) {
                const key = intersections[a];
                var b: isize = @as(isize, @intCast(a));
                while (b > 0 and intersections[@as(usize, @intCast(b - 1))] > key) : (b -= 1) {
                    intersections[@as(usize, @intCast(b))] = intersections[@as(usize, @intCast(b - 1))];
                }
                intersections[@as(usize, @intCast(b))] = key;
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
                    var aa = color;
                    aa.a = @intFromFloat(@as(f32, @floatFromInt(color.a)) * @min(1.0, @max(0.0, @as(f32, @floatFromInt(ixl + 1)) - xl)));
                    self.setPixelAlpha(ixl, y, aa);

                    var x = ixl + 1;
                    if (color.a == 255 and x < ixr and y >= 0) {
                        const word: u32 = (@as(u32, color.r))
                            | (@as(u32, color.g) << 8)
                            | (@as(u32, color.b) << 16)
                            | (@as(u32, color.a) << 24);
                        const clipped_x = if (x < 0) @as(i32, 0) else x;
                        const clipped_ixr = @min(ixr, @as(i32, @intCast(self.width)));
                        if (clipped_x < clipped_ixr) {
                            const row_start = @as(usize, @intCast(y)) * self.bytes_per_row;
                            const span_off = row_start + @as(usize, @intCast(clipped_x)) * 4;
                            const span_words = @as(usize, @intCast(clipped_ixr - clipped_x));
                            const words = @as([*]u32, @ptrCast(@alignCast(self.buf.ptr + span_off)))[0..span_words];
                            @memset(words, word);
                        }
                        x = ixr;
                    }
                    while (x < ixr) : (x += 1) {
                        self.setPixelAlpha(x, y, color);
                    }

                    var aa2 = color;
                    aa2.a = @intFromFloat(@as(f32, @floatFromInt(color.a)) * @min(1.0, @max(0.0, xr - @as(f32, @floatFromInt(ixr)))));
                    self.setPixelAlpha(ixr, y, aa2);
                }
            }
        }
    }

    pub fn drawHeartParticle(self: FrameBuffer, cx: i32, cy: i32, size: f32, fill: Rgba) void {
        var points: [HEART_VERTEX_COUNT][2]i32 = undefined;

        for (heart_unit_vertices, 0..) |uv, i| {
            points[i] = .{
                cx + @as(i32, @intFromFloat(uv[0] * size)),
                cy + @as(i32, @intFromFloat(uv[1] * size)),
            };
        }

        self.fillPolygon(points[0..], fill);
    }

    pub fn drawDiamondParticle(self: FrameBuffer, cx: i32, cy: i32, size: f32, fill: Rgba) void {
        const s: i32 = @intFromFloat(size);
        if (s < 1) return;
        const points = [_][2]i32{
            .{ cx, cy - s },
            .{ cx + s, cy },
            .{ cx, cy + s },
            .{ cx - s, cy },
        };
        self.fillPolygon(points[0..], fill);
    }

    pub fn drawChar(self: FrameBuffer, x: i32, y: i32, ch: u8, char_scale: u32, color: Rgba) void {
        const idx = business.charIndex(ch);
        if (idx >= business.FONT_3X5.len) return;

        const glyph = business.FONT_3X5[idx];
        if (char_scale >= 2 and color.a == 255) {
            const word: u32 = (@as(u32, color.r))
                | (@as(u32, color.g) << 8)
                | (@as(u32, color.b) << 16)
                | (@as(u32, color.a) << 24);
            const cs: i32 = @intCast(char_scale);
            var row: usize = 0;
            while (row < 5) : (row += 1) {
                const bits = glyph[row];
                var col: usize = 0;
                while (col < 3) : (col += 1) {
                    if ((bits >> @as(u3, @intCast(2 - col))) & 1 == 1) {
                        const bx = x + @as(i32, @intCast(col * char_scale));
                        const by = y + @as(i32, @intCast(row * char_scale));
                        var dy: i32 = 0;
                        while (dy < cs) : (dy += 1) {
                            const row_off = @as(usize, @intCast(by + dy)) * self.bytes_per_row + @as(usize, @intCast(bx)) * 4;
                            const words = @as([*]u32, @ptrCast(@alignCast(self.buf.ptr + row_off)))[0..char_scale];
                            @memset(words, word);
                        }
                    }
                }
            }
        } else {
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
