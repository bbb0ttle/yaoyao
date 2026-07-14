pub const Rgba = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const white = Rgba{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black = Rgba{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const heart_bg = Rgba{ .r = 169, .g = 229, .b = 214, .a = 255 };
    pub const heart_fill = white;
    pub const heart_stroke = Rgba{ .r = 219, .g = 236, .b = 230, .a = 255 };
    pub const timer_text = white;
};

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return Vec2{ .x = self.x + other.x, .y = self.y + other.y };
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = @import("std").testing;

test "Vec2.add" {
    const a = Vec2{ .x = 1.0, .y = 2.0 };
    const b = Vec2{ .x = 3.0, .y = -1.0 };
    const r = a.add(b);
    try testing.expectApproxEqAbs(4.0, r.x, 1e-6);
    try testing.expectApproxEqAbs(1.0, r.y, 1e-6);
}
