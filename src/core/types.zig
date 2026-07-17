//! Shared primitive types: color, 2D vector.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.types);

/// 8-bit RGBA color with named palette constants.
pub const Rgba = struct {
    const Self = @This();

    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const WHITE = Rgba{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const BLACK = Rgba{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const HEART_BG = Rgba{ .r = 169, .g = 229, .b = 214, .a = 255 };
    pub const HEART_FILL = WHITE;
    pub const HEART_STROKE = Rgba{ .r = 219, .g = 236, .b = 230, .a = 255 };
    pub const TIMER_TEXT = WHITE;
};

/// 2D vector with floating-point components.
pub const Vec2 = struct {
    const Self = @This();

    x: f32,
    y: f32,

    pub fn add(self: Self, other: Self) Self {
        return Self{ .x = self.x + other.x, .y = self.y + other.y };
    }
};
