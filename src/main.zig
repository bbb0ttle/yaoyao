const std = @import("std");
const app = @import("app.zig");

var canvas: app.Canvas = undefined;
var mouse: app.Mouse = .{ .x = 0, .y = 0, .on_canvas = false };

export fn init() void {
    canvas = app.Canvas.init(std.heap.page_allocator);
}

export fn get_framebuffer_ptr() usize {
    if (canvas.buf.len == 0) return 0;
    return @intFromPtr(&canvas.buf[0]);
}

export fn get_width() u32 {
    return canvas.width;
}

export fn get_height() u32 {
    return canvas.height;
}

export fn set_mouse(x: i32, y: i32, on_canvas: i32) void {
    mouse.x = x;
    mouse.y = y;
    mouse.on_canvas = on_canvas != 0;
}

export fn resize(new_w: u32, new_h: u32) void {
    canvas.resize(new_w, new_h) catch return;
}

export fn update_frame(time: f32) void {
    _ = time;
    const fb = canvas.frameBuffer();
    fb.clear(.{ .r = 255, .g = 255, .b = 255, .a = 255 });
    if (mouse.on_canvas) {
        app.drawCursor(fb, mouse.x, mouse.y);
    }
}
