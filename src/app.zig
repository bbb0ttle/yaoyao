const std = @import("std");
const business = @import("core/business.zig");
const Rgba = business.Rgba;

/// Owns the framebuffer lifecycle — allocation, resize, deinit.
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

/// Lightweight view over a pixel buffer — borrows, never owns.
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
};

pub const Mouse = struct {
    x: i32,
    y: i32,
    on_canvas: bool,
};

pub fn drawCursor(fb: FrameBuffer, mouse_x: i32, mouse_y: i32) void {
    const x0 = mouse_x;
    const y0 = mouse_y;
    const x1 = mouse_x + 28;
    const y1 = mouse_y + 16;
    const x2 = mouse_x + 14;
    const y2 = mouse_y + 30;

    fb.fillTriangle(x0, y0, x1, y1, x2, y2, Rgba.black);
}
