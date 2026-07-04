const std = @import("std");
const app = @import("app.zig");

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
    const fb = app.FrameBuffer{ .buf = framebuffer, .width = width, .height = height };
    const new_fb = fb.resize(new_w, new_h, allocator) catch {
        framebuffer = &[_]u8{};
        width = new_w;
        height = new_h;
        return;
    };
    if (framebuffer.len != 0) allocator.free(framebuffer);
    framebuffer = new_fb.buf;
    width = new_fb.width;
    height = new_fb.height;
}

export fn update_frame(time: f32) void {
    _ = time;
    const fb = app.FrameBuffer{ .buf = framebuffer, .width = width, .height = height };
    fb.clear(.{ .r = 255, .g = 255, .b = 255, .a = 255 });
    if (mouse_on_canvas) {
        app.drawCursor(fb, mouse_x, mouse_y);
    }
}
