const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;

const GpuState = @import("graphics/gpu_state.zig").GpuState;
const text_renderer = @import("graphics/text_renderer.zig");
const ParticlePool = @import("particles/pool.zig").ParticlePool;
const HeartSystem = @import("systems/heart_system.zig").HeartSystem;
const MeteorSystem = @import("systems/meteor_system.zig").MeteorSystem;
const Rng = @import("random.zig").Rng;
const Vec2 = @import("core/types.zig").Vec2;

const POOL_CAPACITY: usize = 10000;

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
        };
        return self;
    }

    pub fn deinit(self: *App) void {
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
        self._meteor_from_heart(x, y);
        self._spawn_burst(x, y);
    }

    pub fn handle_resize(self: *App) void {
        self.resize_cooldown = 30;
        self.heart_ready = false;
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
