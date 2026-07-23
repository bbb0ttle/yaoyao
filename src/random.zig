//! Pseudorandom number generator using a linear congruential engine.

/// Pseudorandom number generator with seedable LCG state.
pub const Rng = struct {
    const Self = @This();

    state: u64,

    pub fn init(seed: u64) Self {
        return Self{ .state = seed };
    }

    pub fn random_range(self: *Self, lo: f32, hi: f32) f32 {
        self.state = self.state *% 6364136223846793005 +% 1442695040888963407;
        const r = @as(f32, @floatFromInt((self.state >> 33) & 0x7FFFFFFF)) / @as(f32, @floatFromInt(0x7FFFFFFF));
        return lo + (hi - lo) * r;
    }

    pub fn random_index(self: *Self, n: usize) usize {
        self.state = self.state *% 6364136223846793005 +% 1442695040888963407;
        const r = (self.state >> 33) & 0x7FFFFFFF;
        return @intCast(r % n);
    }
};
