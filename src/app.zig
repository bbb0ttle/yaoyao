const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;

const GpuState = @import("graphics/gpu_state.zig").GpuState;
const text_renderer = @import("graphics/text_renderer.zig");
const ParticlePool = @import("particles/pool.zig").ParticlePool;
const HeartSystem = @import("systems/heart_system.zig").HeartSystem;
const meteor_sys = @import("systems/meteor_system.zig");
const MeteorSystem = meteor_sys.MeteorSystem;
const Particle = @import("particles/particle.zig").Particle;
const MAX_PARTICLE_SIZE = @import("particles/particle.zig").MAX_PARTICLE_SIZE;
const Rng = @import("random.zig").Rng;
const Vec2 = @import("core/types.zig").Vec2;

const POOL_CAPACITY: usize = 5000;
const DAYS_COUNTER_DEFAULT_START_MS: f64 = 1660694400000.0;

const IncomingHeart = struct {
    particle: *Particle,
    event_id: []const u8,
    target_x: f32,
    target_y: f32,
};

pub const HeartTapCallback = ?*const fn (event_id: [*:0]const u8) callconv(.c) void;

pub const App = struct {
    gpu: GpuState,
    pool: ParticlePool,
    heart: HeartSystem,
    meteor: MeteorSystem,
    rng: Rng,
    allocator: std.mem.Allocator,

    heart_ready: bool,
    meteor_ready: bool,
    transition_start: f32,
    resize_cooldown: u32,
    dpr: f32,
    start_time: f32,

    days_text_buf: [32]u8,
    days_text_len: usize,

    tagged_hearts: std.StringHashMap(*Particle),
    incoming_hearts: std.ArrayList(IncomingHeart),
    days_counter_start_ms: f64,
    heart_tap_callback: HeartTapCallback,

    pub fn init(allocator: std.mem.Allocator) !*App {
        const gpu = try GpuState.init(allocator);
        const pool = try ParticlePool.init(allocator, POOL_CAPACITY);
        const rng = Rng.init(12345);

        const self = try allocator.create(App);
        self.* = .{
            .gpu = gpu,
            .pool = pool,
            .heart = undefined,
            .meteor = undefined,
            .rng = rng,
            .allocator = allocator,
            .heart_ready = false,
            .meteor_ready = false,
            .transition_start = 0.0,
            .resize_cooldown = 0,
            .dpr = sapp.dpiScale(),
            .start_time = @floatCast(sapp.frameDuration()),
            .days_text_buf = undefined,
            .days_text_len = 0,
            .tagged_hearts = std.StringHashMap(*Particle).init(allocator),
            .incoming_hearts = .empty,
            .days_counter_start_ms = DAYS_COUNTER_DEFAULT_START_MS,
            .heart_tap_callback = null,
        };
        return self;
    }

    pub fn deinit(self: *App) void {
        for (self.incoming_hearts.items) |cm| {
            self.allocator.free(cm.event_id);
        }
        self.incoming_hearts.deinit(self.allocator);
        self.tagged_hearts.deinit();
        self.pool.deinit();
        self.gpu.deinit();
        self.allocator.destroy(self);
    }

    pub fn tick_elapsed(self: *App) f32 {
        const elapsed = self.start_time;
        self.start_time += @as(f32, @floatCast(sapp.frameDuration()));
        return elapsed;
    }

    pub fn cooldown_tick(self: *App) void {
        if (self.resize_cooldown > 0) {
            self.resize_cooldown -= 1;
        }
    }

    pub fn needs_system_init(self: *App) bool {
        return self.resize_cooldown == 0 and !self.heart_ready;
    }

    pub fn can_render(self: *App) bool {
        return self.heart_ready and self.resize_cooldown == 0;
    }

    pub fn gpu_mut(self: *App) *GpuState {
        return &self.gpu;
    }

    pub fn init_systems(self: *App, w: f32, h: f32, elapsed: f32) void {
        self.dpr = sapp.dpiScale();
        const dpr = self.dpr;
        const hx: f32 = w / 2.0 - 50.0 * dpr;
        const hy: f32 = h / 2.0 - 200.0 * dpr;
        const fp_x: f32 = w / 2.0 - 50.0 * dpr;
        const fp_y: f32 = h - 80.0 * dpr;

        self.heart = HeartSystem.init(&self.pool, &self.rng, elapsed, hx, hy, h, fp_x, fp_y, dpr);
        self.heart_ready = true;
        self.transition_start = elapsed;

        if (!self.meteor_ready) {
            self.meteor = MeteorSystem.init(w, h, dpr);
            self.meteor_ready = true;
        }
    }

    pub fn update_and_fill_buffers(self: *App, w: f32, h: f32, elapsed: f32, dpr: f32) void {
        const t: f32 = @min(1.0, (elapsed - self.transition_start) / 3.0);

        self._update_day_counter();

        self.heart.update(elapsed, &self.pool, &self.rng);
        if (self.meteor_ready) {
            self.meteor.update(&self.pool, &self.rng);
        }
        self._update_incoming_hearts(elapsed);
        self.pool.collect_alive();

        for (self.pool.alive_slice()) |idx| {
            self.pool.get_particle(idx).update(elapsed, dpr);
        }

        var inst_count = text_renderer.fill_particle_instances(
            &self.gpu,
            &self.pool,
            w,
            h,
            dpr,
            t,
            0,
        );

        if (self.days_text_len > 0) {
            inst_count = text_renderer.fill_text_instances(
                &self.gpu,
                w,
                h,
                dpr,
                &self.days_text_buf,
                self.days_text_len,
                &self.heart,
                inst_count,
            );
        }

        self.gpu.instance_count = inst_count;
    }

    pub fn handle_click(self: *App, x: f32, y: f32) void {
        if (!self.meteor_ready or !self.heart_ready) return;
        if (self._handle_heart_tap(x, y)) {
            self._spawn_burst(x, y);
            return;
        }
        self._meteor_from_heart(x, y);
        self._spawn_burst(x, y);
    }

    pub fn handle_resize(self: *App) void {
        self.resize_cooldown = 30;
        self.heart_ready = false;
    }

    pub fn spawn_heart(self: *App, event_id: []const u8, elapsed: f32) !void {
        const dpr = self.dpr;
        const w = sapp.widthf();
        const h = sapp.heightf();

        if (self.tagged_hearts.contains(event_id)) return;

        for (self.incoming_hearts.items) |cm| {
            if (std.mem.eql(u8, cm.event_id, event_id)) return;
        }

        const id_dup = try self.allocator.allocSentinel(u8, event_id.len, 0);
        @memcpy(id_dup[0..event_id.len], event_id);
        errdefer self.allocator.free(id_dup);

        const min_dist = MAX_PARTICLE_SIZE * dpr * 4.0;
        var dest_x: f32 = undefined;
        var dest_y: f32 = undefined;
        var attempt: usize = 0;
        while (attempt < 30) : (attempt += 1) {
            const dx = self.rng.random_range(w * 0.12, w * 0.88);
            const dy = self.rng.random_range(h * 0.68, h * 0.76);
            if (!self._overlaps_existing(dx, dy, min_dist)) {
                dest_x = dx;
                dest_y = dy;
                break;
            }
        }
        if (attempt >= 20) {
            dest_x = self.rng.random_range(w * 0.12, w * 0.88);
            dest_y = self.rng.random_range(h * 0.68, h * 0.76);
        }

        const speed = meteor_sys.METEOR_SPEED * dpr;
        const angle = std.math.atan2(h, w);
        const vx = -@cos(angle) * speed;
        const vy = @sin(angle) * speed;

        const start_x = w + 40.0 * dpr;
        const t = (start_x - dest_x) / (-vx);
        const start_y = dest_y - vy * t;

        const meteor_size = meteor_sys.METEOR_SIZE * dpr * self.rng.random_range(0.5, 1.0);
        const particle = self.pool.alloc_particle(
            Vec2{ .x = start_x, .y = start_y },
            elapsed,
            .{ .immortal = true, .meteor = true, .size = meteor_size },
            &self.rng,
        );
        particle.set_vel(vx, vy);

        try self.incoming_hearts.append(self.allocator, .{
            .particle = particle,
            .event_id = id_dup,
            .target_x = dest_x,
            .target_y = dest_y,
        });
    }

    pub fn remove_heart(self: *App, event_id: []const u8) void {
        if (self.tagged_hearts.fetchRemove(event_id)) |kv| {
            kv.value.set_fading_out(true);
            self.allocator.free(kv.key);
        }
    }

    pub fn sync_hearts(self: *App, active_ids: [:0]const u8) void {
        var active_set = std.StringHashMap(void).init(self.allocator);
        defer active_set.deinit();

        var split_iter = std.mem.splitScalar(u8, active_ids, '\n');
        while (split_iter.next()) |id| {
            if (id.len > 0) {
                active_set.put(id, {}) catch continue;
            }
        }

        var stale_ids: std.ArrayList([]const u8) = .empty;
        defer stale_ids.deinit(self.allocator);

        var heart_it = self.tagged_hearts.iterator();
        while (heart_it.next()) |entry| {
            if (!active_set.contains(entry.key_ptr.*)) {
                stale_ids.append(self.allocator, entry.key_ptr.*) catch continue;
            }
        }

        for (stale_ids.items) |id| {
            self.remove_heart(id);
        }

        var mi: usize = 0;
        while (mi < self.incoming_hearts.items.len) {
            const cm = self.incoming_hearts.items[mi];
            if (!active_set.contains(cm.event_id)) {
                cm.particle.set_alive(false);
                self.allocator.free(cm.event_id);
                _ = self.incoming_hearts.swapRemove(mi);
            } else {
                mi += 1;
            }
        }
    }

    pub fn set_heart_tap_callback(self: *App, cb: HeartTapCallback) void {
        self.heart_tap_callback = cb;
    }

    pub fn set_days_counter_start_ms(self: *App, ms: f64) void {
        self.days_counter_start_ms = ms;
    }

    fn _handle_heart_tap(self: *App, x: f32, y: f32) bool {
        if (self.heart_tap_callback == null) return false;

        var it = self.tagged_hearts.iterator();
        while (it.next()) |entry| {
            const p = entry.value_ptr.*;
            if (!p.is_alive()) continue;
            const dx = x - p.pos_x();
            const dy = y - p.pos_y();
            const dist = @sqrt(dx * dx + dy * dy);
            if (dist < p.get_size() * 2.0) {
                const key: [*:0]const u8 = @ptrCast(entry.key_ptr.ptr);
                self.heart_tap_callback.?(key);
                return true;
            }
        }
        return false;
    }

    fn _overlaps_existing(self: *App, x: f32, y: f32, min_dist: f32) bool {
        var it = self.tagged_hearts.iterator();
        while (it.next()) |entry| {
            const p = entry.value_ptr.*;
            if (!p.is_alive()) continue;
            const dx = x - p.pos_x();
            const dy = y - p.pos_y();
            if (@sqrt(dx * dx + dy * dy) < min_dist) return true;
        }
        for (self.incoming_hearts.items) |cm| {
            const dx = x - cm.target_x;
            const dy = y - cm.target_y;
            if (@sqrt(dx * dx + dy * dy) < min_dist) return true;
        }
        return false;
    }

    fn _update_day_counter(self: *App) void {
        var ts: std.c.timespec = undefined;
        _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
        const unix_ms: f64 = @as(f64, @floatFromInt(ts.sec)) * 1000.0 + @as(f64, @floatFromInt(ts.nsec)) / 1_000_000.0;
        const start_ms: f64 = self.days_counter_start_ms;
        const diff_days = (unix_ms - start_ms) / (1000.0 * 60.0 * 60.0 * 24.0);
        const int_part: u64 = @intFromFloat(@floor(diff_days));
        const frac: f64 = diff_days - @floor(diff_days);

        self.days_text_len = 0;
        _format_uint(&self.days_text_buf, &self.days_text_len, int_part);

        if (self.days_text_len < self.days_text_buf.len) {
            self.days_text_buf[self.days_text_len] = '.';
            self.days_text_len += 1;
        }

        var f = frac;
        var digits: usize = 0;
        while (digits < 10) : (digits += 1) {
            f *= 10.0;
            const d: u8 = @intFromFloat(@floor(f));
            f -= @floor(f);
            if (self.days_text_len < self.days_text_buf.len) {
                self.days_text_buf[self.days_text_len] = '0' + d;
                self.days_text_len += 1;
            }
        }

        const suffix = " DAYS";
        for (suffix) |byte| {
            if (self.days_text_len < self.days_text_buf.len) {
                self.days_text_buf[self.days_text_len] = byte;
                self.days_text_len += 1;
            }
        }

        if (self.days_text_len < self.days_text_buf.len) {
            self.days_text_buf[self.days_text_len] = 0;
        }
    }

    fn _meteor_from_heart(self: *App, target_x: f32, target_y: f32) void {
        var spawns: [30]Vec2 = undefined;
        self.heart.fill_contour_positions(&spawns);
        self.meteor.falling(
            &self.pool,
            &self.rng,
            target_x,
            target_y,
            self.heart.center_x(),
            self.heart.center_y(),
            spawns[0..],
        );
    }

    fn _spawn_burst(self: *App, x: f32, y: f32) void {
        const dpr = self.dpr;
        const count: usize = @intFromFloat(self.rng.random_range(25.0, 45.0));

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const p = self.pool.alloc_particle(
                Vec2{ .x = x, .y = y },
                0,
                .{ .size = self.rng.random_range(5.0, 10.0) * dpr },
                &self.rng,
            );
            p.set_vel(
                self.rng.random_range(-1.0, 1.0) * dpr,
                self.rng.random_range(-1.5, 2.5) * dpr,
            );
            p.set_acc(0, 0.2);
            p.set_lifespan(self.rng.random_range(80.0, 120.0));
        }
    }

    fn _update_incoming_hearts(self: *App, elapsed: f32) void {
        const dpr = self.dpr;
        var i: usize = 0;
        while (i < self.incoming_hearts.items.len) {
            const p = self.incoming_hearts.items[i].particle;
            if (!p.is_alive()) {
                self.allocator.free(self.incoming_hearts.items[i].event_id);
                _ = self.incoming_hearts.swapRemove(i);
                continue;
            }

            const prev_x = p.pos_x();
            const prev_y = p.pos_y();
            p.translate_by_vel();

            const trail = self.pool.alloc_particle(
                Vec2{ .x = prev_x, .y = prev_y },
                elapsed,
                .{ .size = meteor_sys.TRAIL_SIZE * dpr },
                &self.rng,
            );
            trail.set_vel(0, 0);
            trail.set_acc(0, 0);
            trail.set_lifespan(meteor_sys.TRAIL_LIFESPAN);

            const tx = self.incoming_hearts.items[i].target_x;
            const ty = self.incoming_hearts.items[i].target_y;
            const adx = tx - p.pos_x();
            const ady = ty - p.pos_y();
            const dist = @sqrt(adx * adx + ady * ady);
            const past_target = (p.vel_x() * adx + p.vel_y() * ady) < 0;

            if (dist < 20.0 * dpr or past_target) {
                self._transition_incoming_heart(i, elapsed);
                continue;
            }

            i += 1;
        }
    }

    fn _transition_incoming_heart(self: *App, index: usize, elapsed: f32) void {
        const cm = self.incoming_hearts.items[index];
        const p = cm.particle;
        const event_id = cm.event_id;

        p.set_pos(cm.target_x, cm.target_y);
        p.set_immortal(false);
        p.set_meteor(false);
        p.set_floating(true);
        p.set_beat(true);
        p.set_lifespan(self.rng.random_range(75.0, 110.0));
        p.set_birth_sec(elapsed);
        p.set_size_scale(self.rng.random_range(0.55, 1.0));
        p.set_size(MAX_PARTICLE_SIZE * self.dpr);
        p.set_vel(
            self.rng.random_range(-0.5, 0.5) * self.dpr,
            self.rng.random_range(-2.5, -1.5) * self.dpr,
        );

        self.tagged_hearts.put(event_id, p) catch {
            std.log.warn("tagged_hearts.put failed, discarding heart for event_id", .{});
            self.allocator.free(event_id);
            p.set_alive(false);
        };

        _ = self.incoming_hearts.swapRemove(index);
    }
};

fn _format_uint(buf: []u8, len: *usize, n: u64) void {
    if (n == 0) {
        if (len.* < buf.len) {
            buf[len.*] = '0';
            len.* += 1;
        }
        return;
    }
    var tmp: [20]u8 = undefined;
    var tlen: usize = 0;
    var v = n;
    while (v > 0) : (v /= 10) {
        tmp[tlen] = @as(u8, @intCast(v % 10)) + '0';
        tlen += 1;
    }
    var j: usize = tlen;
    while (j > 0) {
        j -= 1;
        if (len.* < buf.len) {
            buf[len.*] = tmp[j];
            len.* += 1;
        }
    }
}
