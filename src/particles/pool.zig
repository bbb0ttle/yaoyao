//! ParticlePool with free-list allocation and alive-index tracking.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.pool);

const Particle = @import("particle.zig").Particle;
const ParticleOpts = @import("particle.zig").ParticleOpts;
const Vec2 = @import("../core/types.zig").Vec2;
const Rng = @import("../random.zig").Rng;

const SENTINEL: usize = std.math.maxInt(usize);

/// Object pool for particles with free-list reuse and alive-index tracking.
pub const ParticlePool = struct {
    const Self = @This();

    particles: []Particle,
    alive_indices: []usize,
    alive_count: usize,
    len: usize,
    free_head: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
        const particles = try allocator.alloc(Particle, capacity);
        errdefer allocator.free(particles);
        const alive_indices = try allocator.alloc(usize, capacity);
        return Self{
            .particles = particles,
            .alive_indices = alive_indices,
            .alive_count = 0,
            .len = 0,
            .free_head = SENTINEL,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.particles);
        self.allocator.free(self.alive_indices);
        self.* = undefined;
    }

    pub fn reset(self: *Self) void {
        self.len = 0;
        self.free_head = SENTINEL;
        self.alive_count = 0;
    }

    /// Compact the alive list in place (swap-remove semantics preserving
    /// order) and push dead slots onto the persistent free list.
    /// Runs in O(alive) instead of scanning the whole backing array.
    pub fn collect_alive(self: *Self) void {
        var write: usize = 0;
        var read: usize = 0;
        while (read < self.alive_count) : (read += 1) {
            const idx = self.alive_indices[read];
            if (self.particles[idx].is_alive()) {
                self.alive_indices[write] = idx;
                write += 1;
            } else {
                self.particles[idx].set_next_free(self.free_head);
                self.free_head = idx;
            }
        }
        self.alive_count = write;
    }

    pub fn alloc_particle(self: *Self, pos: Vec2, elapsed: f32, opts: ParticleOpts, rng: *Rng) *Particle {
        var idx: usize = undefined;
        if (self.free_head < SENTINEL) {
            idx = self.free_head;
            self.free_head = self.particles[idx].get_next_free();
        } else if (self.len < self.particles.len) {
            idx = self.len;
            self.len += 1;
        } else {
            // Pool exhausted: overwrite slot 0. The free list is empty by
            // definition here, so bookkeeping stays consistent.
            idx = 0;
        }
        self.particles[idx] = Particle.init(pos, elapsed, opts, rng);
        self.alive_indices[self.alive_count] = idx;
        self.alive_count += 1;
        return &self.particles[idx];
    }

    pub fn alive_slice(self: *const Self) []usize {
        return self.alive_indices[0..self.alive_count];
    }

    pub fn get_particle(self: *Self, idx: usize) *Particle {
        return &self.particles[idx];
    }

    pub fn get_len(self: *const Self) usize {
        return self.len;
    }

    pub fn get_alive_count(self: *const Self) usize {
        return self.alive_count;
    }
};
