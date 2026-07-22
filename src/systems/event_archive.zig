//! Bounded FIFO archive of event ids whose hearts have left the screen.
//! Owns the id strings; sampling for memory replay borrows them.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Rng = @import("../random.zig").Rng;

/// FIFO archive with a hard cap: putting into a full archive frees the
/// oldest entry. A hash index over the same slices (list owns, index
/// borrows) keeps membership checks O(1) at archive scale.
pub const ArchiveList = struct {
    const Self = @This();

    alloc: Allocator,
    ids: std.ArrayList([]const u8),
    index: std.StringHashMap(void),
    cap: usize,

    pub fn init(alloc: Allocator, cap: usize) Self {
        return .{ .alloc = alloc, .ids = .empty, .index = std.StringHashMap(void).init(alloc), .cap = cap };
    }

    pub fn deinit(self: *Self) void {
        for (self.ids.items) |id| self.alloc.free(id);
        self.ids.deinit(self.alloc);
        self.index.deinit();
        self.* = undefined;
    }

    pub fn len(self: *const Self) usize {
        return self.ids.items.len;
    }

    /// Take ownership of `id`, freeing the oldest entry first when full.
    pub fn put(self: *Self, id: []const u8) !void {
        if (self.index.contains(id)) {
            self.alloc.free(id);
            return;
        }
        if (self.ids.items.len >= self.cap) {
            const oldest = self.ids.orderedRemove(0);
            _ = self.index.remove(oldest);
            self.alloc.free(oldest);
        }
        errdefer self.alloc.free(id);
        try self.ids.append(self.alloc, id);
        errdefer _ = self.ids.pop();
        try self.index.put(id, {});
    }

    /// Free and drop `id` if archived. Returns whether it was present.
    pub fn remove(self: *Self, id: []const u8) bool {
        const kv = self.index.fetchRemove(id) orelse return false;
        for (self.ids.items, 0..) |item, i| {
            if (item.ptr == kv.key.ptr) {
                self.alloc.free(item);
                _ = self.ids.orderedRemove(i);
                return true;
            }
        }
        unreachable; // index and list share every slice
    }

    pub fn contains(self: *const Self, id: []const u8) bool {
        return self.index.contains(id);
    }

    /// Drop every entry absent from `active` (calendar sync reconciliation).
    pub fn retain_only(self: *Self, active: *const std.StringHashMap(void)) void {
        var i: usize = 0;
        while (i < self.ids.items.len) {
            if (!active.contains(self.ids.items[i])) {
                _ = self.index.remove(self.ids.items[i]);
                self.alloc.free(self.ids.items[i]);
                _ = self.ids.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Fill `out` with up to `count` unique random entry indices; returns
    /// the fill count (capped by the archive length).
    pub fn sample_indices(self: *const Self, count: usize, rng: *Rng, out: []usize) usize {
        const n = @min(count, self.ids.items.len);
        var filled: usize = 0;
        while (filled < n) {
            const idx = rng.random_index(self.ids.items.len);
            var dup = false;
            for (out[0..filled]) |existing| {
                if (existing == idx) {
                    dup = true;
                    break;
                }
            }
            if (!dup) {
                out[filled] = idx;
                filled += 1;
            }
        }
        return n;
    }
};
