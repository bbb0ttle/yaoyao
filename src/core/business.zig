pub const Rgba = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const white = Rgba{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black = Rgba{ .r = 0, .g = 0, .b = 0, .a = 255 };
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
