/// Writes the decimal representation of n into buf, returns the written slice.
pub fn formatUint(n: u64, buf: []u8) []u8 {
    if (n == 0) {
        buf[0] = '0';
        return buf[0..1];
    }
    var tmp: [20]u8 = undefined;
    var tlen: usize = 0;
    var v = n;
    while (v > 0) : (v /= 10) {
        tmp[tlen] = @as(u8, @intCast(v % 10)) + '0';
        tlen += 1;
    }
    var idx: usize = 0;
    var j: usize = tlen;
    while (j > 0) {
        j -= 1;
        buf[idx] = tmp[j];
        idx += 1;
    }
    return buf[0..tlen];
}

const std = @import("std");

test "formatUint zero" {
    var buf: [20]u8 = undefined;
    const s = formatUint(0, &buf);
    try std.testing.expectEqualStrings("0", s);
}

test "formatUint positive" {
    var buf: [20]u8 = undefined;
    const s = formatUint(12345, &buf);
    try std.testing.expectEqualStrings("12345", s);
}

test "formatUint large number" {
    var buf: [20]u8 = undefined;
    const s = formatUint(9999999999, &buf);
    try std.testing.expectEqualStrings("9999999999", s);
}
