const std = @import("std");

var width: u32 = 800;
var height: u32 = 600;
var framebuffer: []u8 = &[_]u8{};

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

export fn update_frame(time: f32) void {
    _ = time;
    var i: usize = 0;
    while (i < framebuffer.len) : (i += 4) {
        framebuffer[i + 0] = 255;
        framebuffer[i + 1] = 255;
        framebuffer[i + 2] = 255;
        framebuffer[i + 3] = 255;
    }
}
