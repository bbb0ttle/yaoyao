const std = @import("std");

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

    pub fn copy(self: Vec2) Vec2 {
        return Vec2{ .x = self.x, .y = self.y };
    }
};

pub fn sortVerticesByY(v0: [2]i32, v1: [2]i32, v2: [2]i32) [3][2]i32 {
    var v = [_][2]i32{ v0, v1, v2 };
    if (v[0][1] > v[1][1]) {
        const tmp = v[0];
        v[0] = v[1];
        v[1] = tmp;
    }
    if (v[0][1] > v[2][1]) {
        const tmp = v[0];
        v[0] = v[2];
        v[2] = tmp;
    }
    if (v[1][1] > v[2][1]) {
        const tmp = v[1];
        v[1] = v[2];
        v[2] = tmp;
    }
    return v;
}

/// Parametric heart curve. t in [0, 2π], result in [-2, 2] for x, roughly [-2.5, 1.5] for y.
pub fn createHeartPos(t: f32) Vec2 {
    const s = @sin(t);
    const x = 2.0 * s * s * s;
    const y = -(2.0 * ((13.0 * @cos(t) - 5.0 * @cos(2.0 * t) - 2.0 * @cos(3.0 * t) - @cos(4.0 * t)) / 16.0));
    return Vec2{ .x = x, .y = y };
}

/// Smooth periodic oscillation suitable for breathing effects.
/// Returns a value in [min, max] that oscillates with period ~0.67s.
pub fn breath(sec: f32, min: f32, max: f32) f32 {
    const e = std.math.e;
    const a = 1.0 / e;
    const b = e - a;
    return (@exp(@sin(sec * 3.0 * std.math.pi)) - a) * (max - min) / b + min;
}

/// Linear interpolation: returns t * b / a.
pub fn scale(val: f32, a: f32, b: f32) f32 {
    return val * b / a;
}

/// 3x5 bitmap font for digits 0-9 and '.'.
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
        else => 22,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "Vec2.add" {
    const a = Vec2{ .x = 1.0, .y = 2.0 };
    const b = Vec2{ .x = 3.0, .y = -1.0 };
    const r = a.add(b);
    try testing.expectApproxEqAbs(4.0, r.x, 1e-6);
    try testing.expectApproxEqAbs(1.0, r.y, 1e-6);
}

test "Vec2.copy" {
    var a = Vec2{ .x = 5.0, .y = 7.0 };
    const b = a.copy();
    a.x = 99.0;
    try testing.expectApproxEqAbs(5.0, b.x, 1e-6);
    try testing.expectApproxEqAbs(7.0, b.y, 1e-6);
}

test "createHeartPos at t=0" {
    const p = createHeartPos(0.0);
    try testing.expectApproxEqAbs(0.0, p.x, 1e-6);
    try testing.expectApproxEqAbs(-0.625, p.y, 1e-6);
}

test "createHeartPos at t=pi" {
    const p = createHeartPos(std.math.pi);
    try testing.expectApproxEqAbs(0.0, p.x, 1e-4);
    try testing.expect(p.y > 0.0);
}

test "breath within bounds" {
    for (0..100) |i| {
        const t = @as(f32, @floatFromInt(i)) * 0.01;
        const v = breath(t, 10.0, 20.0);
        try testing.expect(v >= 10.0);
        try testing.expect(v <= 20.0);
    }
}

test "scale linear" {
    try testing.expectApproxEqAbs(50.0, scale(100.0, 200.0, 100.0), 1e-6);
    try testing.expectApproxEqAbs(0.0, scale(0.0, 200.0, 100.0), 1e-6);
    try testing.expectApproxEqAbs(75.0, scale(150.0, 200.0, 100.0), 1e-6);
}

test "charIndex digits" {
    for (0..10) |i| {
        try testing.expectEqual(i, charIndex(@as(u8, @intCast('0' + i))));
    }
}

test "charIndex special chars" {
    try testing.expectEqual(@as(usize, 10), charIndex('.'));
    try testing.expectEqual(@as(usize, 11), charIndex(' '));
    try testing.expectEqual(@as(usize, 22), charIndex('?'));
}

test "font glyphs are 3-bit valid" {
    for (FONT_3X5, 0..) |glyph, gi| {
        for (glyph) |row| {
            try testing.expect(row <= 0b111);
        }
        _ = gi;
    }
}

test "sortVerticesByY ordering" {
    const sorted = sortVerticesByY(.{ 0, 10 }, .{ 0, 5 }, .{ 0, 0 });
    try testing.expectEqual(@as(i32, 0), sorted[0][1]);
    try testing.expectEqual(@as(i32, 5), sorted[1][1]);
    try testing.expectEqual(@as(i32, 10), sorted[2][1]);
}
