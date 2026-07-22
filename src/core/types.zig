//! Shared primitive types: color, 2D vector.


/// 8-bit RGBA color with named palette constants.
pub const Rgba = struct {
    const Self = @This();

    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const WHITE = Rgba{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const BLACK = Rgba{ .r = 0, .g = 0, .b = 0, .a = 255 };
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
