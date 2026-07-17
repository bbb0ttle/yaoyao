const std = @import("std");
const testing = std.testing;
const Rng = @import("random.zig").Rng;

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
