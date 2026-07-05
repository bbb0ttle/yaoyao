const font = @import("font.zig");
const FrameBuffer = @import("FrameBuffer.zig").FrameBuffer;
const Rgba = @import("types.zig").Rgba;

pub fn drawChar(fb: FrameBuffer, x: i32, y: i32, ch: u8, char_scale: u32, color: Rgba) void {
    const idx = font.charIndex(ch);
    if (idx >= font.FONT_3X5.len) return;

    const glyph = font.FONT_3X5[idx];
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
                        fb.setPixel(
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

pub fn drawText(fb: FrameBuffer, x: i32, y: i32, text: []const u8, char_scale: u32, color: Rgba) void {
    const char_width: i32 = @as(i32, @intCast(3 * char_scale + char_scale));
    var cx = x;
    for (text) |ch| {
        drawChar(fb, cx, y, ch, char_scale, color);
        cx += char_width;
    }
}
