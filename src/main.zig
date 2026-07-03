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

    if (framebuffer.len != 0) {
        allocator.free(framebuffer);
        framebuffer = &[_]u8{};
    }

    if (new_len == 0) {
        width = new_w;
        height = new_h;
        return;
    }

    framebuffer = allocator.alloc(u8, new_len) catch {
        framebuffer = &[_]u8{};
        return;
    };

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
