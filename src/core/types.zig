pub const Rgba = struct {
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

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return Vec2{ .x = self.x + other.x, .y = self.y + other.y };
    }
};
