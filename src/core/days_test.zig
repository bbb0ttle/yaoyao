const std = @import("std");
const testing = std.testing;
const days = @import("days.zig");

test "format_days zero renders the placeholder" {
    var buf: [32]u8 = undefined;
    const len = days.format_days(&buf, 0.0);
    try testing.expectEqualStrings("0.0000000000 DAYS", buf[0..len]);
}

test "format_days integer and fraction" {
    var buf: [32]u8 = undefined;
    const len = days.format_days(&buf, 123.4567890123);
    try testing.expectEqualStrings("123.4567890123 DAYS", buf[0..len]);
}

test "format_days truncates the fraction at ten digits" {
    var buf: [32]u8 = undefined;
    const len = days.format_days(&buf, 1.99999999999);
    try testing.expectEqualStrings("1.9999999999 DAYS", buf[0..len]);
}

test "format_days large integer part" {
    var buf: [32]u8 = undefined;
    const len = days.format_days(&buf, 12345.0);
    try testing.expectEqualStrings("12345.0000000000 DAYS", buf[0..len]);
}

test "format_days terminates with NUL when room allows" {
    var buf: [32]u8 = undefined;
    const len = days.format_days(&buf, 0.0);
    try testing.expectEqual(@as(u8, 0), buf[len]);
}

test "format_days clips safely into a tight buffer" {
    var buf: [8]u8 = undefined;
    const len = days.format_days(&buf, 123.4567890123);
    try testing.expectEqualStrings("123.4567", buf[0..8]);
    try testing.expectEqual(@as(usize, 8), len);
}
