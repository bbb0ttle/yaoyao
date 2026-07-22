//! Cooldown emission for freshly landed tagged hearts: each landing
//! continuously emits particles until cold. Emission count, gravity, and
//! alpha all decay with intensity — the heart has arrived, so the stream
//! loses energy as it settles into silence.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Vec2 = @import("../core/types.zig").Vec2;
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const Rng = @import("../random.zig").Rng;

const COOLING_DURATION_MIN: f32 = 2.5;
const COOLING_DURATION_MAX: f32 = 4.5;
// Per-frame emission rate at full intensity (k=1); the actual per-frame
// count is round(EMIT_RATE * k), so the stream thins out as the heart cools.
const EMIT_RATE: usize = 2;
// The continuous stream falls downward in a loose fan from just below the
// heart's bottom edge, keeping the heart's own silhouette clear of embers.
// The landing burst stays omnidirectional — it is the momentary arrival
// gush.
const STREAM_VX_SPREAD: f32 = 0.7;
const STREAM_VY_MIN: f32 = 0.4;
const STREAM_VY_MAX: f32 = 2.0;
const STREAM_ORIGIN_OFFSET: f32 = 2.0;
// Initial landing pop: a short burst at full intensity to mark the arrival.
const LAND_BURST_MIN: usize = 16;
const LAND_BURST_MAX: usize = 24;
// Per-emitter velocity scale is rolled once at landing.
const VEL_SCALE_MIN: f32 = 0.85;
const VEL_SCALE_MAX: f32 = 1.15;

/// Emission intensity decay: 1.0 at landing, following a quadratic
/// ease-out curve — quick initial drop, gentle settle into silence.
pub fn intensity(age_sec: f32, duration_sec: f32) f32 {
    const t = std.math.clamp(age_sec / duration_sec, 0.0, 1.0);
    const inv = 1.0 - t;
    return inv * inv;
}

const Emitter = struct {
    x: f32,
    y: f32,
    event_id: []u8,
    birth_sec: f32,
    vel_scale: f32,
    duration: f32,
};

fn emit_particles(x: f32, y: f32, count: usize, vel_scale: f32, k: f32, vx_spread: f32, vy_min: f32, vy_max: f32, pool: *ParticlePool, rng: *Rng, dpr: f32) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const p = pool.alloc_particle(Vec2{ .x = x, .y = y }, 0, .{
            .cooling = true,
            .size = rng.random_range(8.0, 10.0) * dpr,
        }, rng);
        p.set_vel(
            rng.random_range(-vx_spread, vx_spread) * dpr * vel_scale,
            rng.random_range(vy_min, vy_max) * dpr * vel_scale,
        );
        p.set_acc(0, 0.2 * k);
        p.set_alpha_scale(0.15 + 0.85 * k);
        p.set_lifespan(rng.random_range(70.0, 100.0));
    }
}

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

        const burst_count = LAND_BURST_MIN + rng.random_index(LAND_BURST_MAX - LAND_BURST_MIN + 1);
        const vel_scale = rng.random_range(VEL_SCALE_MIN, VEL_SCALE_MAX);
        const duration = rng.random_range(COOLING_DURATION_MIN, COOLING_DURATION_MAX);
        try self.emitters.append(self.alloc, Emitter{
            .x = x,
            .y = y,
            .event_id = id_dup,
            .birth_sec = elapsed,
            .vel_scale = vel_scale,
            .duration = duration,
        });
        emit_particles(x, y, burst_count, vel_scale, 1.0, 0.3, -1.2, 2.0, pool, rng, dpr);
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

    /// Every frame, each active emitter releases a small stream of
    /// particles. Emission count scales with intensity — round(EMIT_RATE * k)
    /// — alongside gravity and alpha, so the stream weakens as it cools.
    pub fn update(self: *Self, elapsed: f32, pool: *ParticlePool, rng: *Rng, dpr: f32) void {
        var i: usize = 0;
        while (i < self.emitters.items.len) {
            const e = &self.emitters.items[i];
            const age = elapsed - e.birth_sec;
            if (age > e.duration) {
                self.alloc.free(e.event_id);
                _ = self.emitters.swapRemove(i);
                continue;
            }
            const k = intensity(age, e.duration);
            const count: usize = @intFromFloat(@round(@as(f32, @floatFromInt(EMIT_RATE)) * k));
            emit_particles(e.x, e.y + STREAM_ORIGIN_OFFSET * dpr, count, e.vel_scale, k, STREAM_VX_SPREAD, STREAM_VY_MIN, STREAM_VY_MAX, pool, rng, dpr);
            i += 1;
        }
    }

    fn release_all(self: *Self) void {
        for (self.emitters.items) |e| {
            self.alloc.free(e.event_id);
        }
    }
};
