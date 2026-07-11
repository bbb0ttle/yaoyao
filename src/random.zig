var rng_state: u64 = 12345;

pub fn randomRange(lo: f32, hi: f32) f32 {
    rng_state = rng_state *% 6364136223846793005 +% 1442695040888963407;
    const r = @as(f32, @floatFromInt((rng_state >> 33) & 0x7FFFFFFF)) / @as(f32, @floatFromInt(0x7FFFFFFF));
    return lo + (hi - lo) * r;
}

pub fn randomIndex(n: usize) usize {
    rng_state = rng_state *% 6364136223846793005 +% 1442695040888963407;
    const r = (rng_state >> 33) & 0x7FFFFFFF;
    return @intCast(r % n);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = @import("std").testing;

test "randomRange within bounds" {
    const lo: f32 = 10.0;
    const hi: f32 = 20.0;
    for (0..100) |_| {
        const v = randomRange(lo, hi);
        try testing.expect(v >= lo);
        try testing.expect(v < hi);
    }
}

test "randomIndex within bounds" {
    for (0..50) |_| {
        const v = randomIndex(7);
        try testing.expect(v < 7);
    }
}

test "random deterministic sequence" {
    rng_state = 12345;
    const a = randomRange(0.0, 1.0);
    rng_state = 12345;
    const b = randomRange(0.0, 1.0);
    try testing.expectApproxEqAbs(a, b, 1e-6);
}
