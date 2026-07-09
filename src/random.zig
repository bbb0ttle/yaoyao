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
