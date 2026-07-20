//! Cooldown emission for freshly landed tagged hearts: each landing sheds
//! falling heart particles at an exponentially decaying rate until cold.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.heart_cooling);

const Vec2 = @import("../core/types.zig").Vec2;
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const Rng = @import("../random.zig").Rng;

const COOLING_DURATION_SEC: f32 = 3.0;
const COOLING_TAU_SEC: f32 = 0.8;
// Landing burst: close to spawn_burst intensity for a proper gush, but with
// shorter lifespans and tighter velocities so the spread stays contained.
const LAND_BURST_MIN: usize = 18;
const LAND_BURST_MAX: usize = 26;
const EMIT_MIN_GAP_SEC: f32 = 0.12;
const EMIT_MAX_GAP_SEC: f32 = 1.0;

/// Emission intensity decay: 1.0 at landing, cooling towards zero.
pub fn intensity(age_sec: f32) f32 {
    return @exp(-age_sec / COOLING_TAU_SEC);
}

fn emit_gap_sec(age_sec: f32) f32 {
    return std.math.clamp(EMIT_MIN_GAP_SEC / intensity(age_sec), EMIT_MIN_GAP_SEC, EMIT_MAX_GAP_SEC);
}

const Emitter = struct {
    x: f32,
    y: f32,
    event_id: []u8,
    birth_sec: f32,
    next_emit_sec: f32,
};

/// Tracks cooling emitters per landed heart, keyed by event id. Positions
/// are copied coordinates, never particle pointers, so a pool reset cannot
/// leave dangling references here.
pub const HeartCooling = struct {
    const Self = @This();

    alloc: Allocator,
    emitters: std.ArrayList(Emitter),

    pub fn init(alloc: Allocator) Self {
        return Self{
            .alloc = alloc,
            .emitters = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.release_all();
        self.emitters.deinit(self.alloc);
        self.* = undefined;
    }

    /// Register a landed heart and fire its landing burst.
    pub fn add(self: *Self, x: f32, y: f32, event_id: []const u8, elapsed: f32, pool: *ParticlePool, rng: *Rng, dpr: f32) !void {
        const id_dup = try self.alloc.dupe(u8, event_id);
        errdefer self.alloc.free(id_dup);

        try self.emitters.append(self.alloc, Emitter{
            .x = x,
            .y = y,
            .event_id = id_dup,
            .birth_sec = elapsed,
            .next_emit_sec = elapsed + EMIT_MIN_GAP_SEC,
        });
        emit_burst(x, y, pool, rng, dpr);
    }

    /// Stop cooling for a heart that is being removed.
    pub fn cancel(self: *Self, event_id: []const u8) void {
        var i: usize = 0;
        while (i < self.emitters.items.len) : (i += 1) {
            if (std.mem.eql(u8, self.emitters.items[i].event_id, event_id)) {
                self.alloc.free(self.emitters.items[i].event_id);
                _ = self.emitters.swapRemove(i);
                return;
            }
        }
    }

    /// Drop all emitters, e.g. when a resize resets the particle pool.
    pub fn clear(self: *Self) void {
        self.release_all();
        self.emitters.clearRetainingCapacity();
    }

    pub fn update(self: *Self, elapsed: f32, pool: *ParticlePool, rng: *Rng, dpr: f32) void {
        var i: usize = 0;
        while (i < self.emitters.items.len) {
            const e = &self.emitters.items[i];
            const age = elapsed - e.birth_sec;
            if (age > COOLING_DURATION_SEC) {
                self.alloc.free(e.event_id);
                _ = self.emitters.swapRemove(i);
                continue;
            }
            if (elapsed >= e.next_emit_sec) {
                emit_one(e.x, e.y, pool, rng, dpr);
                e.next_emit_sec += emit_gap_sec(age);
            }
            i += 1;
        }
    }

    fn release_all(self: *Self) void {
        for (self.emitters.items) |e| {
            self.alloc.free(e.event_id);
        }
    }
};

fn emit_burst(x: f32, y: f32, pool: *ParticlePool, rng: *Rng, dpr: f32) void {
    const count = LAND_BURST_MIN + rng.random_index(LAND_BURST_MAX - LAND_BURST_MIN + 1);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const p = pool.alloc_particle(Vec2{ .x = x, .y = y }, 0, .{
            .size = rng.random_range(8.0, 10.0) * dpr,
        }, rng);
        p.set_vel(
            rng.random_range(-0.9, 0.9) * dpr,
            rng.random_range(-1.2, 2.0) * dpr,
        );
        p.set_acc(0, 0.2);
        p.set_lifespan(rng.random_range(70.0, 100.0));
    }
}

fn emit_one(x: f32, y: f32, pool: *ParticlePool, rng: *Rng, dpr: f32) void {
    const p = pool.alloc_particle(Vec2{ .x = x, .y = y }, 0, .{
        .size = rng.random_range(8.0, 10.0) * dpr,
    }, rng);
    p.set_vel(
        rng.random_range(-0.6, 0.6) * dpr,
        rng.random_range(0.5, 2.0) * dpr,
    );
    p.set_acc(0, 0.2);
    p.set_lifespan(rng.random_range(70.0, 110.0));
}
