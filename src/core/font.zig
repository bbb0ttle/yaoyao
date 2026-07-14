pub const FONT_3X5: [22][5]u8 = .{
    .{ 0b111, 0b101, 0b101, 0b101, 0b111 }, // 0
    .{ 0b010, 0b110, 0b010, 0b010, 0b111 }, // 1
    .{ 0b111, 0b001, 0b111, 0b100, 0b111 }, // 2
    .{ 0b111, 0b001, 0b111, 0b001, 0b111 }, // 3
    .{ 0b101, 0b101, 0b111, 0b001, 0b001 }, // 4
    .{ 0b111, 0b100, 0b111, 0b001, 0b111 }, // 5
    .{ 0b111, 0b100, 0b111, 0b101, 0b111 }, // 6
    .{ 0b111, 0b001, 0b001, 0b001, 0b001 }, // 7
    .{ 0b111, 0b101, 0b111, 0b101, 0b111 }, // 8
    .{ 0b111, 0b101, 0b111, 0b001, 0b111 }, // 9
    .{ 0b000, 0b000, 0b000, 0b000, 0b010 }, // .
    .{ 0b000, 0b000, 0b000, 0b000, 0b000 }, // (space)
    .{ 0b111, 0b100, 0b100, 0b100, 0b111 }, // [
    .{ 0b111, 0b001, 0b001, 0b001, 0b111 }, // ]
    .{ 0b001, 0b001, 0b111, 0b101, 0b111 }, // d
    .{ 0b010, 0b000, 0b111, 0b101, 0b111 }, // a
    .{ 0b101, 0b101, 0b111, 0b001, 0b110 }, // y
    .{ 0b011, 0b100, 0b010, 0b001, 0b110 }, // s
    .{ 0b110, 0b101, 0b101, 0b101, 0b110 }, // D
    .{ 0b010, 0b101, 0b111, 0b101, 0b101 }, // A
    .{ 0b101, 0b101, 0b111, 0b010, 0b010 }, // Y
    .{ 0b011, 0b100, 0b010, 0b001, 0b110 }, // S
};

pub fn char_index(c: u8) usize {
    return switch (c) {
        '0'...'9' => c - '0',
        '.' => 10,
        ' ' => 11,
        '[' => 12,
        ']' => 13,
        'd' => 14,
        'a' => 15,
        'y' => 16,
        's' => 17,
        'D' => 18,
        'A' => 19,
        'Y' => 20,
        'S' => 21,
        else => 22,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = @import("std").testing;

test "char_index digits" {
    for (0..10) |i| {
        try testing.expectEqual(i, char_index(@as(u8, @intCast('0' + i))));
    }
}

test "char_index special chars" {
    try testing.expectEqual(@as(usize, 10), char_index('.'));
    try testing.expectEqual(@as(usize, 11), char_index(' '));
    try testing.expectEqual(@as(usize, 22), char_index('?'));
}

test "font glyphs are 3-bit valid" {
    for (FONT_3X5, 0..) |glyph, gi| {
        for (glyph) |row| {
            try testing.expect(row <= 0b111);
        }
        _ = gi;
    }
}
