/// 3x5 bitmap font for digits 0-9, '.', space, brackets, and "days DAYS" letters.
/// Each row is stored in the low 3 bits of a u8. Row 0 = top.
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

pub fn charIndex(c: u8) usize {
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
        else => 11, // unknown chars map to space
    };
}

const std = @import("std");

test "charIndex digits" {
    try std.testing.expectEqual(@as(usize, 0), charIndex('0'));
    try std.testing.expectEqual(@as(usize, 9), charIndex('9'));
}

test "charIndex letters" {
    try std.testing.expectEqual(@as(usize, 18), charIndex('D'));
    try std.testing.expectEqual(@as(usize, 19), charIndex('A'));
    try std.testing.expectEqual(@as(usize, 20), charIndex('Y'));
    try std.testing.expectEqual(@as(usize, 21), charIndex('S'));
}

test "charIndex dot" {
    try std.testing.expectEqual(@as(usize, 10), charIndex('.'));
}

test "charIndex unknown maps to space" {
    try std.testing.expectEqual(@as(usize, 11), charIndex('x'));
    try std.testing.expectEqual(@as(usize, 11), charIndex('?'));
}
