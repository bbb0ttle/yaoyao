const std = @import("std");

var width: u32 = 800;
var height: u32 = 600;
var framebuffer: []u8 = &[_]u8{};

var mouse_x: i32 = 0;
var mouse_y: i32 = 0;
var mouse_on_canvas: bool = false;

export fn get_framebuffer_ptr() usize {
    if (framebuffer.len == 0) return 0;
    return @intFromPtr(&framebuffer[0]);
}

export fn get_width() u32 {
    return width;
}

export fn get_height() u32 {
    return height;
}

export fn set_mouse(x: i32, y: i32, on_canvas: i32) void {
    mouse_x = x;
    mouse_y = y;
    mouse_on_canvas = on_canvas != 0;
}

export fn resize(new_w: u32, new_h: u32) void {
    const allocator = std.heap.page_allocator;
    const new_len: usize = @as(usize, new_w) * @as(usize, new_h) * 4;

    if (new_len == 0) {
        if (framebuffer.len != 0) {
            allocator.free(framebuffer);
            framebuffer = &[_]u8{};
        }
        width = new_w;
        height = new_h;
        return;
    }

    const new_buf = allocator.alloc(u8, new_len) catch {
        framebuffer = &[_]u8{};
        width = new_w;
        height = new_h;
        return;
    };

    if (framebuffer.len != 0) {
        const old_w = width;
        const old_h = height;
        const copy_w: u32 = if (new_w < old_w) new_w else old_w;
        const copy_h: u32 = if (new_h < old_h) new_h else old_h;

        var y: u32 = 0;
        while (y < copy_h) : (y += 1) {
            const old_row_start: usize = @as(usize, y) * @as(usize, old_w) * 4;
            const new_row_start: usize = @as(usize, y) * @as(usize, new_w) * 4;
            const row_bytes: usize = @as(usize, copy_w) * 4;
            @memcpy(new_buf[new_row_start..][0..row_bytes], framebuffer[old_row_start..][0..row_bytes]);
        }

        allocator.free(framebuffer);
    }

    framebuffer = new_buf;
    width = new_w;
    height = new_h;
}

fn setPixel(x: i32, y: i32, r: u8, g: u8, b: u8, a: u8) void {
    if (x < 0 or x >= @as(i32, @intCast(width))) return;
    if (y < 0 or y >= @as(i32, @intCast(height))) return;
    const idx = (@as(usize, @intCast(y)) * @as(usize, width) + @as(usize, @intCast(x))) * 4;
    framebuffer[idx] = r;
    framebuffer[idx + 1] = g;
    framebuffer[idx + 2] = b;
    framebuffer[idx + 3] = a;
}

fn fillTriangle(x0: i32, y0: i32, x1: i32, y1: i32, x2: i32, y2: i32, r: u8, g: u8, b: u8, a: u8) void {
    var v = [_][2]i32{
        .{ x0, y0 },
        .{ x1, y1 },
        .{ x2, y2 },
    };
    // sort by y
    if (v[0][1] > v[1][1]) {
        const tmp = v[0];
        v[0] = v[1];
        v[1] = tmp;
    }
    if (v[0][1] > v[2][1]) {
        const tmp = v[0];
        v[0] = v[2];
        v[2] = tmp;
    }
    if (v[1][1] > v[2][1]) {
        const tmp = v[1];
        v[1] = v[2];
        v[2] = tmp;
    }

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
            setPixel(x, y, r, g, b, a);
        }
    }
}

fn drawCursor() void {
    const tx = mouse_x;
    const ty = mouse_y;

    const x0 = tx;
    const y0 = ty;
    const x1 = tx + 28;
    const y1 = ty + 16;
    const x2 = tx + 14;
    const y2 = ty + 30;

    // solid black arrow
    fillTriangle(x0, y0, x1, y1, x2, y2, 0, 0, 0, 255);
}

export fn update_frame(time: f32) void {
    _ = time;
    var i: usize = 0;
    while (i < framebuffer.len) : (i += 4) {
        framebuffer[i + 0] = 255;
        framebuffer[i + 1] = 255;
        framebuffer[i + 2] = 255;
        framebuffer[i + 3] = 255;
    }

    if (mouse_on_canvas) {
        drawCursor();
    }
}
