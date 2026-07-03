const std = @import("std");

pub const width: u32 = 800;
pub const height: u32 = 600;

var framebuffer: [width * height * 4]u8 = undefined;

export fn get_framebuffer_ptr() [*]u8 {
    return &framebuffer;
}

export fn get_width() u32 {
    return width;
}

export fn get_height() u32 {
    return height;
}

export fn update_frame(time: f32) void {
    var i: usize = 0;
    while (i < framebuffer.len) : (i += 4) {
        const pixel_index = i / 4;
        const x: f32 = @floatFromInt(pixel_index % width);
        const y: f32 = @floatFromInt(pixel_index / width);

        framebuffer[i + 0] = @intFromFloat((x / @as(f32, @floatFromInt(width))) * 255.0);
        framebuffer[i + 1] = @intFromFloat((y / @as(f32, @floatFromInt(height))) * 255.0);
        framebuffer[i + 2] = @intFromFloat(@mod(time * 50.0, 255.0));
        framebuffer[i + 3] = 255;
    }
}
