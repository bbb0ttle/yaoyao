pub const Rgba = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const white = Rgba{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black = Rgba{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const heart_bg = Rgba{ .r = 251, .g = 192, .b = 93, .a = 255 };
    pub const heart_fill = Rgba{ .r = 251, .g = 93, .b = 99, .a = 255 };
    pub const heart_stroke = Rgba{ .r = 251, .g = 192, .b = 93, .a = 255 };
    pub const timer_text = Rgba{ .r = 251, .g = 93, .b = 99, .a = 255 };
};

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return Vec2{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn copy(self: Vec2) Vec2 {
        return Vec2{ .x = self.x, .y = self.y };
    }
};

const std = @import("std");

test "Rgba constants" {
    try std.testing.expectEqual(@as(u8, 255), Rgba.white.r);
    try std.testing.expectEqual(@as(u8, 255), Rgba.white.a);
    try std.testing.expectEqual(@as(u8, 0), Rgba.black.r);
    try std.testing.expectEqual(@as(u8, 251), Rgba.heart_bg.r);
    try std.testing.expectEqual(@as(u8, 192), Rgba.heart_bg.g);
    try std.testing.expectEqual(@as(u8, 99), Rgba.heart_fill.b);
}

test "Vec2.add" {
    const a = Vec2{ .x = 1.0, .y = 2.0 };
    const b = Vec2{ .x = 3.0, .y = 4.0 };
    const c = a.add(b);
    try std.testing.expectEqual(@as(f32, 4.0), c.x);
    try std.testing.expectEqual(@as(f32, 6.0), c.y);
}

test "Vec2.copy" {
    const a = Vec2{ .x = 1.5, .y = -2.5 };
    const b = a.copy();
    try std.testing.expectEqual(a.x, b.x);
    try std.testing.expectEqual(a.y, b.y);
}
