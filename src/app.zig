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

const CalendarMeteor = struct {
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

    calendar_hearts: std.StringHashMap(*Particle),
    calendar_meteors: std.ArrayList(CalendarMeteor),
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
            .calendar_hearts = std.StringHashMap(*Particle).init(allocator),
            .calendar_meteors = .empty,
            .heart_tap_callback = null,
        };
        return self;
    }

    pub fn deinit(self: *App) void {
        for (self.calendar_meteors.items) |cm| {
            self.allocator.free(cm.event_id);
        }
        self.calendar_meteors.deinit(self.allocator);
        self.calendar_hearts.deinit();
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
        self._update_calendar_meteors(elapsed);
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
        if (self._handle_heart_tap(x, y)) return;
        self._meteor_from_heart(x, y);
        self._spawn_burst(x, y);
    }

    pub fn handle_resize(self: *App) void {
        self.resize_cooldown = 30;
        self.heart_ready = false;
    }

    pub fn spawn_calendar_heart(self: *App, event_id: []const u8, elapsed: f32) !void {
        const dpr = self.dpr;
        const w = sapp.widthf();
        const h = sapp.heightf();

        if (self.calendar_hearts.contains(event_id)) return;

        for (self.calendar_meteors.items) |cm| {
            if (std.mem.eql(u8, cm.event_id, event_id)) return;
        }

        const id_dup = try self.allocator.allocSentinel(u8, event_id.len, 0);
        @memcpy(id_dup[0..event_id.len], event_id);
        errdefer self.allocator.free(id_dup);

        const dest_x = self.rng.random_range(w * 0.3, w * 0.7);
        const dest_y = self.rng.random_range(h * 0.55, h * 0.65);

        const speed = meteor_sys.METEOR_SPEED * dpr;
        const angle = std.math.atan2(h, w);
        const vx = -@cos(angle) * speed;
        const vy = @sin(angle) * speed;

        const start_x = w + 40.0 * dpr;
        const t = (start_x - dest_x) / (-vx);
        const start_y = dest_y - vy * t;

        const particle = self.pool.alloc_particle(
            Vec2{ .x = start_x, .y = start_y },
            elapsed,
            .{ .immortal = true, .meteor = true, .size = meteor_sys.METEOR_SIZE * dpr },
            &self.rng,
        );
        particle.vel.x = vx;
        particle.vel.y = vy;

        try self.calendar_meteors.append(self.allocator, .{
            .particle = particle,
            .event_id = id_dup,
            .target_x = dest_x,
            .target_y = dest_y,
        });
    }

    pub fn remove_calendar_heart(self: *App, event_id: []const u8) void {
        if (self.calendar_hearts.fetchRemove(event_id)) |kv| {
            kv.value.set_alive(false);
            self.allocator.free(kv.key);
        }
    }

    pub fn set_heart_tap_callback(self: *App, cb: HeartTapCallback) void {
        self.heart_tap_callback = cb;
    }

    fn _handle_heart_tap(self: *App, x: f32, y: f32) bool {
        if (self.heart_tap_callback == null) return false;

        var it = self.calendar_hearts.iterator();
        while (it.next()) |entry| {
            const p = entry.value_ptr.*;
            if (!p.is_alive()) continue;
            const dx = x - p.pos.x;
            const dy = y - p.pos.y;
            const dist = @sqrt(dx * dx + dy * dy);
            if (dist < p.size * 2.0) {
                const key: [*:0]const u8 = @ptrCast(entry.key_ptr.ptr);
                self.heart_tap_callback.?(key);
                return true;
            }
        }
        return false;
    }

    fn _update_day_counter(self: *App) void {
        var ts: std.c.timespec = undefined;
        _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
        const unix_ms: f64 = @as(f64, @floatFromInt(ts.sec)) * 1000.0 + @as(f64, @floatFromInt(ts.nsec)) / 1_000_000.0;
        const start_ms: f64 = 1660694400000.0;
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
            p.vel.x = self.rng.random_range(-1.0, 1.0) * dpr;
            p.vel.y = self.rng.random_range(-1.5, 2.5) * dpr;
            p.acc.y = 0.2;
            p.lifespan = self.rng.random_range(80.0, 120.0);
        }
    }

    fn _update_calendar_meteors(self: *App, elapsed: f32) void {
        const dpr = self.dpr;
        var i: usize = 0;
        while (i < self.calendar_meteors.items.len) {
            const p = self.calendar_meteors.items[i].particle;
            if (!p.is_alive()) {
                self.allocator.free(self.calendar_meteors.items[i].event_id);
                _ = self.calendar_meteors.swapRemove(i);
                continue;
            }

            const prev_x = p.pos.x;
            const prev_y = p.pos.y;
            p.pos.x += p.vel.x;
            p.pos.y += p.vel.y;

            const trail = self.pool.alloc_particle(
                Vec2{ .x = prev_x, .y = prev_y },
                elapsed,
                .{ .size = meteor_sys.TRAIL_SIZE * dpr },
                &self.rng,
            );
            trail.vel.x = 0;
            trail.vel.y = 0;
            trail.acc.x = 0;
            trail.acc.y = 0;
            trail.lifespan = meteor_sys.TRAIL_LIFESPAN;

            const tx = self.calendar_meteors.items[i].target_x;
            const ty = self.calendar_meteors.items[i].target_y;
            const adx = tx - p.pos.x;
            const ady = ty - p.pos.y;
            const dist = @sqrt(adx * adx + ady * ady);
            const past_target = (p.vel.x * adx + p.vel.y * ady) < 0;

            if (dist < 20.0 * dpr or past_target) {
                self._transition_calendar_meteor(i, elapsed);
                continue;
            }

            i += 1;
        }
    }

    fn _transition_calendar_meteor(self: *App, index: usize, elapsed: f32) void {
        const cm = self.calendar_meteors.items[index];
        const p = cm.particle;
        const event_id = cm.event_id;

        p.pos.x = cm.target_x;
        p.pos.y = cm.target_y;
        p.flags.meteor = false;
        p.flags.floating = true;
        p.flags.beat = true;
        p.set_birth_sec(elapsed);
        p.size = MAX_PARTICLE_SIZE * self.dpr;
        p.vel.x = self.rng.random_range(-0.5, 0.5) * self.dpr;
        p.vel.y = self.rng.random_range(-2.5, -1.5) * self.dpr;

        self.calendar_hearts.put(event_id, p) catch {
            self.allocator.free(event_id);
            p.set_alive(false);
        };

        _ = self.calendar_meteors.swapRemove(index);
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
