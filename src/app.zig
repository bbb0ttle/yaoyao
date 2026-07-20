//! Core application state, lifecycle, and heart event orchestration.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.app);

const sokol = @import("sokol");
const sapp = sokol.app;

const GpuState = @import("graphics/gpu_state.zig").GpuState;
const text_renderer = @import("graphics/text_renderer.zig");
const ParticlePool = @import("particles/pool.zig").ParticlePool;
const HeartSystem = @import("systems/heart_system.zig").HeartSystem;
const MotionMode = @import("systems/heart_system.zig").MotionMode;
const meteor_sys = @import("systems/meteor_system.zig");
const MeteorSystem = meteor_sys.MeteorSystem;
const NebulaSystem = @import("systems/nebula_system.zig").NebulaSystem;
const HeartCooling = @import("systems/heart_cooling.zig").HeartCooling;
const Particle = @import("particles/particle.zig").Particle;
const MAX_PARTICLE_SIZE = @import("particles/particle.zig").MAX_PARTICLE_SIZE;
const Rng = @import("random.zig").Rng;
const Vec2 = @import("core/types.zig").Vec2;
const theme_mod = @import("core/theme.zig");
const Theme = theme_mod.Theme;
const ThemeTransition = theme_mod.ThemeTransition;

const POOL_CAPACITY: usize = 5000;
pub const DAYS_COUNTER_DEFAULT_START_MS: f64 = 1660694400000.0;

// Landing region for tagged hearts: a wide starfield band between the big
// heart and the bottom day counter.
const LAND_MIN_X: f32 = 0.08;
const LAND_MAX_X: f32 = 0.92;
const LAND_MIN_Y: f32 = 0.45;
const LAND_MAX_Y: f32 = 0.88;

// Placement: most hearts grow near an existing one (clusters), the rest
// scatter freely — the cluster/void contrast of a real starfield.
const CLUSTER_BIAS: f32 = 0.6;

// Older hearts shrink as new ones land, like stars receding into depth,
// keeping the newest event the most prominent.
const HEART_SHRINK_FACTOR: f32 = 0.94;
const HEART_MIN_SIZE_SCALE: f32 = 0.38;

// Spawn bursts (initial calendar sync) beyond this budget skip the fly-in
// and fade in directly at their destinations, so a full day's events does
// not turn the canvas into a meteor storm. Spawns within the window count
// as one batch; single event additions always fly in.
const MAX_FLY_IN_HEARTS: usize = 3;
const SPAWN_BATCH_WINDOW_SEC: f32 = 1.0;

// Tap feedback pulse for the counter-pair hearts: a quick scale pop that
// eases back to normal.
const COUNTER_TAP_PULSE_SEC: f32 = 0.35;
const COUNTER_TAP_PULSE_SCALE: f32 = 0.6;

// VoiceOver proxy frame padding around the counter pair, in points; covers
// the largest pulsing hit circle.
const COUNTER_ACCESS_PAD_PT: f32 = 30.0;

/// Frame of the counter-pair tap target in logical points, for the iOS
/// accessibility proxy element.
pub const CounterHeartsFrame = extern struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

const IncomingHeart = struct {
    particle: *Particle,
    event_id: []const u8,
    target_x: f32,
    target_y: f32,
    was_touching_contour: bool,
};

/// C ABI callback invoked when a tagged heart is tapped.
pub const HeartTapCallback = ?*const fn (event_id: [*:0]const u8) callconv(.c) void;

/// C ABI callback invoked when either counter-pair heart is tapped.
pub const CounterTapCallback = ?*const fn () callconv(.c) void;

/// Core application: owns GPU state, particle pool, heart/meteor systems, and tagged heart map.
pub const App = struct {
    const Self = @This();

    gpu: GpuState,
    pool: ParticlePool,
    heart: HeartSystem,
    meteor: MeteorSystem,
    nebula: NebulaSystem,
    rng: Rng,
    allocator: std.mem.Allocator,

    is_heart_ready: bool,
    is_meteor_ready: bool,
    is_nebula_ready: bool,
    nebula_enabled: bool,
    transition_start: f32,
    resize_cooldown: u32,
    dpr: f32,
    start_time: f32,
    last_elapsed: f32,
    theme: ThemeTransition,
    theme_id: theme_mod.ThemeId,
    custom_theme: Theme,

    heart_opacity: f32,
    heart_motion: MotionMode,
    heart_y_fraction: ?f32,
    heart_size_scale: f32,

    days_text_buf: [32]u8,
    days_text_len: usize,
    text_layout: text_renderer.TextLayout,

    tagged_hearts: std.StringHashMap(*Particle),
    incoming_hearts: std.ArrayList(IncomingHeart),
    cooling: HeartCooling,
    spawn_batch_count: usize,
    last_spawn_sec: f32,
    days_counter_start_ms: f64,
    is_days_counter_set: bool,
    heart_tap_callback: HeartTapCallback,
    counter_tap_callback: CounterTapCallback,
    counter_tap_pulse_sec: ?f32,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        var gpu = try GpuState.init(allocator);
        errdefer gpu.deinit();
        var pool = try ParticlePool.init(allocator, POOL_CAPACITY);
        errdefer pool.deinit();
        const rng = Rng.init(12345);

        const self = try allocator.create(Self);
        self.* = .{
            .gpu = gpu,
            .pool = pool,
            .heart = undefined,
            .meteor = undefined,
            .nebula = undefined,
            .rng = rng,
            .allocator = allocator,
            .is_heart_ready = false,
            .is_meteor_ready = false,
            .is_nebula_ready = false,
            .nebula_enabled = false,
            .transition_start = 0.0,
            .resize_cooldown = 0,
            .dpr = sapp.dpiScale(),
            .start_time = @floatCast(sapp.frameDuration()),
            .last_elapsed = 0.0,
            .theme = ThemeTransition.init(theme_mod.MINT),
            .theme_id = .mint,
            .custom_theme = theme_mod.MINT,
            .heart_opacity = 1.0,
            .heart_motion = .beat,
            .heart_y_fraction = null,
            .heart_size_scale = 1.0,
            .days_text_buf = undefined,
            .days_text_len = 0,
            .text_layout = .{},
            .tagged_hearts = std.StringHashMap(*Particle).init(allocator),
            .incoming_hearts = .empty,
            .cooling = HeartCooling.init(allocator),
            .spawn_batch_count = 0,
            .last_spawn_sec = -1.0e9,
            .days_counter_start_ms = DAYS_COUNTER_DEFAULT_START_MS,
            .is_days_counter_set = false,
            .heart_tap_callback = null,
            .counter_tap_callback = null,
            .counter_tap_pulse_sec = null,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.incoming_hearts.items) |cm| {
            self.allocator.free(cm.event_id);
        }
        self.incoming_hearts.deinit(self.allocator);
        self.cooling.deinit();
        self.tagged_hearts.deinit();
        self.pool.deinit();
        self.gpu.deinit();
        self.allocator.destroy(self);
        self.* = undefined;
    }

    pub fn tick_elapsed(self: *Self) f32 {
        const elapsed = self.start_time;
        self.start_time += @as(f32, @floatCast(sapp.frameDuration()));
        self.last_elapsed = elapsed;
        return elapsed;
    }

    pub fn cooldown_tick(self: *Self) void {
        if (self.resize_cooldown > 0) {
            self.resize_cooldown -= 1;
        }
    }

    pub fn needs_system_init(self: *Self) bool {
        return self.resize_cooldown == 0 and !self.is_heart_ready;
    }

    pub fn can_render(self: *Self) bool {
        return self.is_heart_ready and self.resize_cooldown == 0;
    }

    pub fn gpu_mut(self: *Self) *GpuState {
        return &self.gpu;
    }

    pub fn init_systems(self: *Self, w: f32, h: f32, elapsed: f32) void {
        self.dpr = sapp.dpiScale();
        const dpr = self.dpr;
        const hx: f32 = self.heart_cx(w, dpr);
        const hy: f32 = self.heart_cy(h, dpr);
        const fp_x: f32 = w / 2.0 - 50.0 * dpr;
        const fp_y: f32 = h - 80.0 * dpr;

        self.heart = HeartSystem.init(&self.pool, &self.rng, elapsed, hx, hy, h, fp_x, fp_y, dpr);
        self.is_heart_ready = true;
        self.transition_start = elapsed;

        if (!self.is_meteor_ready) {
            self.meteor = MeteorSystem.init(w, h, dpr);
            self.is_meteor_ready = true;
        }

        // Heart init resets the pool, wiping any nebula blobs; the next
        // update respawns them when nebula is enabled.
        self.is_nebula_ready = false;
    }

    pub fn update_and_fill_buffers(self: *Self, w: f32, h: f32, elapsed: f32, dpr: f32) void {
        const t: f32 = @min(1.0, (elapsed - self.transition_start) / 3.0);

        self.heart.set_cy(self.heart_cy(h, dpr));
        self.heart.set_cx(self.heart_cx(w, dpr));
        self.heart.set_opacity(self.heart_opacity);
        self.heart.set_motion(self.heart_motion);
        self.heart.set_size_scale(self.heart_size_scale);

        self.update_day_counter();

        if (self.nebula_enabled and !self.is_nebula_ready) {
            self.nebula = NebulaSystem.init(&self.pool, &self.rng, w, h, dpr, elapsed);
            self.is_nebula_ready = true;
        }
        if (self.is_nebula_ready) {
            self.nebula.update(elapsed, w, h);
        }

        self.heart.update(elapsed, &self.pool, &self.rng);
        if (self.is_meteor_ready) {
            self.meteor.update(&self.pool, &self.rng);
        }
        self.update_incoming_hearts(elapsed);
        self.cooling.update(elapsed, &self.pool, &self.rng, dpr);
        self.update_counter_tap_pulse(elapsed);
        self.pool.collect_alive();

        var inst_count = text_renderer.fill_particle_instances(
            &self.gpu,
            &self.pool,
            w,
            h,
            dpr,
            t,
            elapsed,
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
                &self.text_layout,
            );
        }

        self.gpu.set_instance_count(inst_count);
    }

    pub fn handle_click(self: *Self, x: f32, y: f32) void {
        if (!self.is_meteor_ready or !self.is_heart_ready) return;
        self.spawn_burst(x, y);

        if (self.handle_counter_hearts_tap(x, y)) {
            return;
        }
        if (self.handle_heart_tap(x, y)) {
            return;
        }
        // self.meteor_from_heart(x - self.heart.center_x(), y - self.heart.center_y(), .{});
    }

    pub fn handle_resize(self: *Self) void {
        self.resize_cooldown = 30;
        self.is_heart_ready = false;
        self.cooling.clear();
    }

    pub fn spawn_heart(self: *Self, event_id: []const u8, elapsed: f32) !void {
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

        const dest = self.pick_landing_spot(w, h, dpr);

        // Batch tracking uses the frame-driven clock: the `elapsed` passed
        // in from the C ABI is only a frame duration, so it can never
        // measure the quiet gap between separate sync rounds.
        const now = self.last_elapsed;
        if (now - self.last_spawn_sec > SPAWN_BATCH_WINDOW_SEC) {
            self.spawn_batch_count = 0;
        }
        self.last_spawn_sec = now;
        self.spawn_batch_count += 1;

        if (self.spawn_batch_count > MAX_FLY_IN_HEARTS) {
            self.convert_incoming_to_fade_in(now);
            self.spawn_heart_fade_in(id_dup, dest.x, dest.y, now);
            return;
        }

        const speed = meteor_sys.METEOR_SPEED * dpr;
        const angle = std.math.atan2(h, w);
        const vx = -@cos(angle) * speed;
        const vy = @sin(angle) * speed;

        const start_x = w + 40.0 * dpr;
        const t = (start_x - dest.x) / (-vx);
        const start_y = dest.y - vy * t;

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
            .target_x = dest.x,
            .target_y = dest.y,
            .was_touching_contour = false,
        });
    }

    fn pick_landing_spot(self: *Self, w: f32, h: f32, dpr: f32) Vec2 {
        const hard_min = MAX_PARTICLE_SIZE * dpr * 1.6;
        var dest: Vec2 = undefined;
        var placed = false;

        // Cluster branch: grow near a random existing heart, like a star
        // joining its group.
        if (self.rng.random_range(0.0, 1.0) < CLUSTER_BIAS) {
            var tries: usize = 0;
            while (tries < 12 and !placed) : (tries += 1) {
                const anchor = self.random_anchor() orelse break;
                const ang = self.rng.random_range(0.0, 2.0 * std.math.pi);
                const dist = MAX_PARTICLE_SIZE * dpr * self.rng.random_range(1.6, 3.0);
                const cx = anchor.x + @cos(ang) * dist;
                const cy = anchor.y + @sin(ang) * dist;
                if (cx < w * LAND_MIN_X or cx > w * LAND_MAX_X or
                    cy < h * LAND_MIN_Y or cy > h * LAND_MAX_Y) continue;
                if (self.nearest_clearance(cx, cy) < hard_min) continue;
                dest = Vec2{ .x = cx, .y = cy };
                placed = true;
            }
        }

        // Scatter branch (and fallback): uniform random with only the hard
        // spacing floor — casual sampling keeps natural density variance.
        if (!placed) {
            var best_clear: f32 = 0.0;
            var tries: usize = 0;
            while (tries < 15) : (tries += 1) {
                const cx = self.rng.random_range(w * LAND_MIN_X, w * LAND_MAX_X);
                const cy = self.rng.random_range(h * LAND_MIN_Y, h * LAND_MAX_Y);
                const clearance = self.nearest_clearance(cx, cy);
                if (clearance >= hard_min) {
                    dest = Vec2{ .x = cx, .y = cy };
                    placed = true;
                    break;
                }
                if (clearance > best_clear) {
                    best_clear = clearance;
                    dest = Vec2{ .x = cx, .y = cy };
                    placed = true;
                }
            }
            if (!placed) {
                dest = Vec2{
                    .x = self.rng.random_range(w * LAND_MIN_X, w * LAND_MAX_X),
                    .y = self.rng.random_range(h * LAND_MIN_Y, h * LAND_MAX_Y),
                };
            }
        }

        return dest;
    }

    fn spawn_heart_fade_in(self: *Self, event_id: []const u8, x: f32, y: f32, elapsed: f32) void {
        const p = self.pool.alloc_particle(Vec2{ .x = x, .y = y }, elapsed, .{
            .floating = true,
            .beat = true,
            .size = MAX_PARTICLE_SIZE * self.dpr,
        }, &self.rng);
        self.fade_in_heart_at(p, event_id, x, y, elapsed);
    }

    /// Settle a heart directly at its destination with a fade-in ramp, no
    /// fly-in, no cooldown emission. Takes ownership of `event_id`.
    fn fade_in_heart_at(self: *Self, p: *Particle, event_id: []const u8, x: f32, y: f32, elapsed: f32) void {
        p.set_pos(x, y);
        p.set_immortal(false);
        p.set_meteor(false);
        p.set_floating(true);
        p.set_beat(true);
        p.set_lifespan(self.rng.random_range(75.0, 110.0));
        p.set_birth_sec(elapsed);
        p.set_size_scale(self.rng.random_range(0.8, 1.0));
        p.set_size(MAX_PARTICLE_SIZE * self.dpr);
        p.set_alpha_scale(0.0);
        p.set_fading_in(true);

        self.shrink_tagged_hearts();
        self.tagged_hearts.put(event_id, p) catch {
            log.warn("tagged_hearts.put failed, discarding heart for event_id", .{});
            self.allocator.free(event_id);
            p.set_alive(false);
        };
    }

    fn convert_incoming_to_fade_in(self: *Self, elapsed: f32) void {
        for (self.incoming_hearts.items) |cm| {
            self.fade_in_heart_at(cm.particle, cm.event_id, cm.target_x, cm.target_y, elapsed);
        }
        self.incoming_hearts.clearRetainingCapacity();
    }

    fn shrink_tagged_hearts(self: *Self) void {
        // Older hearts recede a step so the newest stays the brightest star.
        var shrink_it = self.tagged_hearts.iterator();
        while (shrink_it.next()) |entry| {
            const old = entry.value_ptr.*;
            old.set_size_scale(@max(HEART_MIN_SIZE_SCALE, old.get_size_scale() * HEART_SHRINK_FACTOR));
        }
    }

    pub fn remove_heart(self: *Self, event_id: []const u8) void {
        if (self.tagged_hearts.fetchRemove(event_id)) |kv| {
            kv.value.set_fading_out(true);
            self.cooling.cancel(event_id);
            self.allocator.free(kv.key);
        }
    }

    pub fn sync_hearts(self: *Self, active_ids: [:0]const u8) void {
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

    pub fn set_heart_tap_callback(self: *Self, cb: HeartTapCallback) void {
        self.heart_tap_callback = cb;
    }

    pub fn set_counter_tap_callback(self: *Self, cb: CounterTapCallback) void {
        self.counter_tap_callback = cb;
    }

    pub fn set_days_counter_start_ms(self: *Self, ms: f64) void {
        self.days_counter_start_ms = ms;
        self.is_days_counter_set = true;
    }

    /// Back to the placeholder state: the counter shows a static
    /// "0.0000000000 DAYS" until a start date is set again.
    pub fn clear_days_counter_start_ms(self: *Self) void {
        self.is_days_counter_set = false;
    }

    pub fn transition_to_theme(self: *Self, theme_id: u32) void {
        const id = std.enums.fromInt(theme_mod.ThemeId, theme_id) orelse {
            log.warn("unknown theme_id={d}, ignoring", .{theme_id});
            return;
        };
        self.theme_id = id;
        self.theme.transition_to(theme_mod.theme_for(id, self.custom_theme), self.last_elapsed);
    }

    pub fn set_custom_theme_color(self: *Self, role_id: u32, r: u8, g: u8, b: u8) void {
        const role = std.enums.fromInt(theme_mod.ColorRole, role_id) orelse {
            log.warn("unknown color role={d}, ignoring", .{role_id});
            return;
        };
        theme_mod.set_color(&self.custom_theme, role, .{ .r = r, .g = g, .b = b, .a = 255 });
        if (self.theme_id == .custom) {
            self.theme.transition_to(self.custom_theme, self.last_elapsed);
        }
    }

    pub fn current_theme(self: *Self) Theme {
        return self.theme.current(self.last_elapsed);
    }

    pub fn set_heart_opacity(self: *Self, opacity: f32) void {
        self.heart_opacity = std.math.clamp(opacity, 0.0, 1.0);
    }

    pub fn set_heart_size_scale(self: *Self, size_scale: f32) void {
        self.heart_size_scale = std.math.clamp(size_scale, 0.3, 3.0);
    }

    pub fn set_heart_motion(self: *Self, mode_id: u32) void {
        const mode = std.enums.fromInt(MotionMode, mode_id) orelse {
            log.warn("unknown heart motion mode={d}, ignoring", .{mode_id});
            return;
        };
        self.heart_motion = mode;
    }

    /// Set the big heart's vertical position as a fraction of canvas height.
    pub fn set_heart_y_fraction(self: *Self, fraction: f32) void {
        self.heart_y_fraction = std.math.clamp(fraction, 0.0, 1.0);
    }

    /// Restore the big heart's built-in vertical position.
    pub fn reset_heart_y(self: *Self) void {
        self.heart_y_fraction = null;
    }

    /// Restore all big-heart settings to their defaults.
    pub fn reset_heart_config(self: *Self) void {
        self.heart_opacity = 1.0;
        self.heart_motion = .beat;
        self.heart_size_scale = 1.0;
        self.heart_y_fraction = null;
    }

    pub fn set_nebula_enabled(self: *Self, enabled: bool) void {
        self.nebula_enabled = enabled;
        if (!enabled and self.is_nebula_ready) {
            self.nebula.clear();
            self.is_nebula_ready = false;
        }
    }

    /// Built-in vertical position as a fraction of the current canvas height.
    pub fn default_heart_y(self: *Self) f32 {
        const h = sapp.heightf();
        return self.legacy_heart_cy(h, sapp.dpiScale()) / h;
    }

    fn heart_cy(self: *Self, h: f32, dpr: f32) f32 {
        if (self.heart_y_fraction) |fraction| {
            return fraction * h;
        }
        return self.legacy_heart_cy(h, dpr);
    }

    // The contour's shape centre sits at cx + 50*dpr*size_scale, so cx is
    // offset by the scaled base to keep the heart visually centred at any size.
    fn heart_cx(self: *Self, w: f32, dpr: f32) f32 {
        return w / 2.0 - 50.0 * dpr * self.heart_size_scale;
    }

    fn legacy_heart_cy(self: *Self, h: f32, dpr: f32) f32 {
        _ = self;
        return h / 2.0 - 200.0 * dpr;
    }

    fn handle_counter_hearts_tap(self: *Self, x: f32, y: f32) bool {
        const cb = self.counter_tap_callback orelse return false;
        const pair = [2]*Particle{ self.heart.float_pair_left(), self.heart.float_pair_right() };
        for (pair) |p| {
            if (!p.is_alive()) continue;
            const dx = x - p.pos_x();
            const dy = y - p.pos_y();
            if (@sqrt(dx * dx + dy * dy) < p.get_size() * 2.5) {
                self.counter_tap_pulse_sec = self.last_elapsed;
                cb();
                return true;
            }
        }
        return false;
    }

    fn update_counter_tap_pulse(self: *Self, elapsed: f32) void {
        const start = self.counter_tap_pulse_sec orelse return;
        const k = @max(0.0, 1.0 - (elapsed - start) / COUNTER_TAP_PULSE_SEC);
        const scale = 1.0 + COUNTER_TAP_PULSE_SCALE * k;
        self.heart.float_pair_left().set_size_scale(scale);
        self.heart.float_pair_right().set_size_scale(scale);
        if (k == 0.0) {
            self.counter_tap_pulse_sec = null;
        }
    }

    /// Union of both counter hearts' tap circles in logical points, for the
    /// iOS VoiceOver proxy. Zero rect while the heart system is not ready.
    pub fn counter_hearts_frame(self: *Self) CounterHeartsFrame {
        if (!self.is_heart_ready) {
            return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
        }
        const dpr = self.dpr;
        const left = self.heart.float_pair_left();
        const right = self.heart.float_pair_right();
        const x0 = @min(left.pos_x(), right.pos_x()) / dpr - COUNTER_ACCESS_PAD_PT;
        const y0 = @min(left.pos_y(), right.pos_y()) / dpr - COUNTER_ACCESS_PAD_PT;
        const x1 = @max(left.pos_x(), right.pos_x()) / dpr + COUNTER_ACCESS_PAD_PT;
        const y1 = @max(left.pos_y(), right.pos_y()) / dpr + COUNTER_ACCESS_PAD_PT;
        return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
    }

    fn handle_heart_tap(self: *Self, x: f32, y: f32) bool {
        if (self.heart_tap_callback == null) return false;

        // Nearest match wins so hearts in dense clusters remain tappable.
        var best_dist = std.math.floatMax(f32);
        var best_key: ?[*:0]const u8 = null;
        var it = self.tagged_hearts.iterator();
        while (it.next()) |entry| {
            const p = entry.value_ptr.*;
            if (!p.is_alive()) continue;
            const dx = x - p.pos_x();
            const dy = y - p.pos_y();
            const dist = @sqrt(dx * dx + dy * dy);
            if (dist < p.get_size() * 2.0 and dist < best_dist) {
                best_dist = dist;
                best_key = @ptrCast(entry.key_ptr.ptr);
            }
        }
        if (best_key) |key| {
            self.heart_tap_callback.?(key);
            return true;
        }
        return false;
    }

    fn nearest_clearance(self: *Self, x: f32, y: f32) f32 {
        var best = std.math.floatMax(f32);
        var it = self.tagged_hearts.iterator();
        while (it.next()) |entry| {
            const p = entry.value_ptr.*;
            if (!p.is_alive()) continue;
            const dx = x - p.pos_x();
            const dy = y - p.pos_y();
            best = @min(best, @sqrt(dx * dx + dy * dy));
        }
        for (self.incoming_hearts.items) |cm| {
            const dx = x - cm.target_x;
            const dy = y - cm.target_y;
            best = @min(best, @sqrt(dx * dx + dy * dy));
        }
        return best;
    }

    /// Reservoir-sample a random anchor among landed hearts and incoming
    /// targets, used as a cluster seed.
    fn random_anchor(self: *Self) ?Vec2 {
        var count: usize = 0;
        var chosen: Vec2 = undefined;
        var it = self.tagged_hearts.iterator();
        while (it.next()) |entry| {
            const p = entry.value_ptr.*;
            if (!p.is_alive()) continue;
            if (self.rng.random_index(count + 1) == 0) {
                chosen = p.get_pos();
            }
            count += 1;
        }
        for (self.incoming_hearts.items) |cm| {
            if (self.rng.random_index(count + 1) == 0) {
                chosen = Vec2{ .x = cm.target_x, .y = cm.target_y };
            }
            count += 1;
        }
        return if (count == 0) null else chosen;
    }

    fn update_day_counter(self: *Self) void {
        // Unset start date: static zero placeholder, no ticking.
        var diff_days: f64 = 0.0;
        if (self.is_days_counter_set) {
            var ts: std.c.timespec = undefined;
            _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
            const unix_ms: f64 = @as(f64, @floatFromInt(ts.sec)) * 1000.0 + @as(f64, @floatFromInt(ts.nsec)) / 1_000_000.0;
            diff_days = (unix_ms - self.days_counter_start_ms) / (1000.0 * 60.0 * 60.0 * 24.0);
        }
        const int_part: u64 = @intFromFloat(@floor(diff_days));
        const frac: f64 = diff_days - @floor(diff_days);

        self.days_text_len = 0;
        format_uint(&self.days_text_buf, &self.days_text_len, int_part);

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

    fn meteor_from_heart(self: *Self, dir_x: f32, dir_y: f32, opts: meteor_sys.MeteorOpts) void {
        var spawns: [30]Vec2 = undefined;
        self.heart.fill_contour_positions(&spawns);
        self.meteor.falling(
            &self.pool,
            &self.rng,
            dir_x,
            dir_y,
            spawns[0..],
            opts,
        );
    }

    fn spawn_burst(self: *Self, x: f32, y: f32) void {
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

    fn update_incoming_hearts(self: *Self, elapsed: f32) void {
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

            // Each fresh contact with the big heart's contour fires one meteor
            // shower travelling parallel to this heart's own trajectory,
            // towards the same destination. Slower and dimmer than the heart
            // so it stays visibly in the lead.
            const touching = self.heart.touches_contour(p.pos_x(), p.pos_y(), p.get_size());
            if (touching and !self.incoming_hearts.items[i].was_touching_contour) {
                self.meteor_from_heart(p.vel_x(), p.vel_y(), .{
                    .force = true,
                    .opacity = 0.65,
                    .speed_scale = 0.6,
                });
            }
            self.incoming_hearts.items[i].was_touching_contour = touching;

            const adx = tx - p.pos_x();
            const ady = ty - p.pos_y();
            const dist = @sqrt(adx * adx + ady * ady);
            const past_target = (p.vel_x() * adx + p.vel_y() * ady) < 0;

            if (dist < 20.0 * dpr or past_target) {
                self.transition_incoming_heart(i, elapsed);
                continue;
            }

            i += 1;
        }
    }

    fn transition_incoming_heart(self: *Self, index: usize, elapsed: f32) void {
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
        p.set_size_scale(self.rng.random_range(0.8, 1.0));
        p.set_size(MAX_PARTICLE_SIZE * self.dpr);
        p.set_vel(
            self.rng.random_range(-0.5, 0.5) * self.dpr,
            self.rng.random_range(-2.5, -1.5) * self.dpr,
        );

        // Older hearts recede a step so the newest stays the brightest star.
        self.shrink_tagged_hearts();

        self.tagged_hearts.put(event_id, p) catch {
            log.warn("tagged_hearts.put failed, discarding heart for event_id", .{});
            self.allocator.free(event_id);
            p.set_alive(false);
            _ = self.incoming_hearts.swapRemove(index);
            return;
        };

        self.cooling.add(cm.target_x, cm.target_y, event_id, elapsed, &self.pool, &self.rng, self.dpr) catch {
            log.warn("cooling.add failed for event_id, skipping cooldown emission", .{});
        };

        _ = self.incoming_hearts.swapRemove(index);
    }
};

fn format_uint(buf: []u8, len: *usize, n: u64) void {
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
