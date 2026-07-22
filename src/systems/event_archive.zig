//! Bounded FIFO archive of event ids whose hearts have left the screen.
//! Owns the id strings; sampling for memory replay borrows them.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Rng = @import("../random.zig").Rng;

/// FIFO archive with a hard cap: putting into a full archive frees the
/// oldest entry. Removal and sync purging keep it consistent with the
/// calendar.
pub const ArchiveList = struct {
    const Self = @This();

    alloc: Allocator,
    ids: std.ArrayList([]const u8),
    cap: usize,

    pub fn init(alloc: Allocator, cap: usize) Self {
        return .{ .alloc = alloc, .ids = .empty, .cap = cap };
    }

    pub fn deinit(self: *Self) void {
        for (self.ids.items) |id| self.alloc.free(id);
        self.ids.deinit(self.alloc);
        self.* = undefined;
    }

    pub fn len(self: *const Self) usize {
        return self.ids.items.len;
    }

    /// Take ownership of `id`, freeing the oldest entry first when full.
    pub fn put(self: *Self, id: []const u8) !void {
        if (self.ids.items.len >= self.cap) {
            self.alloc.free(self.ids.orderedRemove(0));
        }
        errdefer self.alloc.free(id);
        try self.ids.append(self.alloc, id);
    }

    /// Free and drop `id` if archived. Returns whether it was present.
    pub fn remove(self: *Self, id: []const u8) bool {
        for (self.ids.items, 0..) |item, i| {
            if (std.mem.eql(u8, item, id)) {
                self.alloc.free(item);
                _ = self.ids.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn contains(self: *const Self, id: []const u8) bool {
        for (self.ids.items) |item| {
            if (std.mem.eql(u8, item, id)) return true;
        }
        return false;
    }

    /// Drop every entry absent from `active` (calendar sync reconciliation).
    pub fn retain_only(self: *Self, active: *const std.StringHashMap(void)) void {
        var i: usize = 0;
        while (i < self.ids.items.len) {
            if (!active.contains(self.ids.items[i])) {
                self.alloc.free(self.ids.items[i]);
                _ = self.ids.swapRemove(i);
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
