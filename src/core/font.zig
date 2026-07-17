//! 3x5 bitmap font data and character lookup.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.font);

/// 3x5 pixel bitmap font with 22 glyphs (0-9, ., space, brackets, days/Days).
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

/// Maps an ASCII character to its glyph index in FONT_3X5.
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
