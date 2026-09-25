const std = @import("std");
const testing = std.testing;
const font = @import("font.zig");

test "char_index digits" {
    for (0..10) |i| {
        try testing.expectEqual(i, font.char_index(@as(u8, @intCast('0' + i))));
    }
}

test "char_index special chars" {
    try testing.expectEqual(@as(usize, 10), font.char_index('.'));
    try testing.expectEqual(@as(usize, 11), font.char_index(' '));
    try testing.expectEqual(@as(usize, 22), font.char_index('?'));
}

test "font glyphs are 3-bit valid" {
    for (font.FONT_3X5, 0..) |glyph, gi| {
        for (glyph) |row| {
            try testing.expect(row <= 0b111);
        }
        _ = gi;
    }
}
