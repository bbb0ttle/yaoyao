pub const Rng = struct {
    state: u64,

    pub fn init(seed: u64) Rng {
        return Rng{ .state = seed };
    }

    pub fn random_range(self: *Rng, lo: f32, hi: f32) f32 {
        self.state = self.state *% 6364136223846793005 +% 1442695040888963407;
        const r = @as(f32, @floatFromInt((self.state >> 33) & 0x7FFFFFFF)) / @as(f32, @floatFromInt(0x7FFFFFFF));
        return lo + (hi - lo) * r;
    }

    pub fn random_index(self: *Rng, n: usize) usize {
        self.state = self.state *% 6364136223846793005 +% 1442695040888963407;
        const r = (self.state >> 33) & 0x7FFFFFFF;
        return @intCast(r % n);
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = @import("std").testing;

test "random_range within bounds" {
    var rng = Rng.init(12345);
    for (0..100) |_| {
        const v = rng.random_range(10.0, 20.0);
        try testing.expect(v >= 10.0);
        try testing.expect(v < 20.0);
    }
}

test "random_index within bounds" {
    var rng = Rng.init(12345);
    for (0..50) |_| {
        const v = rng.random_index(7);
        try testing.expect(v < 7);
    }
}

test "random deterministic sequence" {
    var a_rng = Rng.init(12345);
    const a = a_rng.random_range(0.0, 1.0);
    var b_rng = Rng.init(12345);
    const b = b_rng.random_range(0.0, 1.0);
    try testing.expectApproxEqAbs(a, b, 1e-6);
}
