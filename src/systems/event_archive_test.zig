const std = @import("std");
const testing = std.testing;
const ArchiveList = @import("event_archive.zig").ArchiveList;
const Rng = @import("../random.zig").Rng;

fn dup(id: []const u8) []u8 {
    return testing.allocator.dupe(u8, id) catch @panic("OOM");
}

test "archive: put keeps entries in FIFO order within cap" {
    var archive = ArchiveList.init(testing.allocator, 3);
    defer archive.deinit();
    try archive.put(dup("a"));
    try archive.put(dup("b"));
    try testing.expectEqual(@as(usize, 2), archive.len());
    try testing.expect(archive.contains("a"));
    try testing.expect(archive.contains("b"));
}

test "archive: put into a full archive evicts and frees the oldest" {
    var archive = ArchiveList.init(testing.allocator, 2);
    defer archive.deinit();
    try archive.put(dup("a"));
    try archive.put(dup("b"));
    try archive.put(dup("c"));
    try testing.expectEqual(@as(usize, 2), archive.len());
    try testing.expect(!archive.contains("a"));
    try testing.expect(archive.contains("b"));
    try testing.expect(archive.contains("c"));
}

test "archive: remove frees the entry and reports presence" {
    var archive = ArchiveList.init(testing.allocator, 4);
    defer archive.deinit();
    try archive.put(dup("a"));
    try testing.expect(archive.remove("a"));
    try testing.expect(!archive.remove("a"));
    try testing.expectEqual(@as(usize, 0), archive.len());
}

test "archive: retain_only purges ids missing from the active set" {
    var archive = ArchiveList.init(testing.allocator, 4);
    defer archive.deinit();
    try archive.put(dup("a"));
    try archive.put(dup("b"));
    try archive.put(dup("c"));

    var active = std.StringHashMap(void).init(testing.allocator);
    defer active.deinit();
    try active.put("b", {});

    archive.retain_only(&active);
    try testing.expectEqual(@as(usize, 1), archive.len());
    try testing.expect(archive.contains("b"));
}

test "archive: sample_indices returns unique in-bounds indices" {
    var archive = ArchiveList.init(testing.allocator, 8);
    defer archive.deinit();
    try archive.put(dup("a"));
    try archive.put(dup("b"));
    try archive.put(dup("c"));

    var rng = Rng.init(12345);
    var out: [8]usize = undefined;
    const n = archive.sample_indices(8, &rng, &out);
    try testing.expectEqual(@as(usize, 3), n); // capped by archive length
    for (out[0..n], 0..) |idx, i| {
        try testing.expect(idx < archive.len());
        for (out[i + 1 .. n]) |other| {
            try testing.expect(idx != other);
        }
    }

    // Empty archive samples nothing.
    var empty = ArchiveList.init(testing.allocator, 8);
    defer empty.deinit();
    try testing.expectEqual(@as(usize, 0), empty.sample_indices(4, &rng, &out));
}
