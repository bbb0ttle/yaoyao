//! Core application state, lifecycle, and heart event orchestration.

const std = @import("std");
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
const ArchiveList = @import("systems/event_archive.zig").ArchiveList;
const Particle = @import("particles/particle.zig").Particle;
const MAX_PARTICLE_SIZE = @import("particles/particle.zig").MAX_PARTICLE_SIZE;
const Rng = @import("random.zig").Rng;
const Vec2 = @import("core/types.zig").Vec2;
const theme_mod = @import("core/theme.zig");
const core_math = @import("core/math.zig");
const days_fmt = @import("core/days.zig");
const platform_time = @import("platform/time.zig");
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

// Ease-out deceleration on the fly-in: the heart enters at twice the
// background meteor speed and stays fast — the power ease-out brakes only
// late and only down to the cruise floor, so the landing itself is the
// payoff: the spring catches the arrival energy in a punchy recoil.
const FLY_START_SPEED: f32 = 16.0; // px/frame × dpr
const FLY_EASE_POWER: f32 = 3.0; // cubic ease-out; higher = later, sharper braking
const FLY_CRUISE_FRAC: f32 = 0.5; // arrival speed as a fraction of entry speed

// Trail dots are laid at this spacing along the flight path, carried
// across frames, so the streak stays evenly dotted no matter how the
// per-frame speed changes (each dot is TRAIL_SIZE wide; half-width
// overlap keeps the trail continuous).
const TRAIL_GAP: f32 = 8.0; // px × dpr

// Follow-through settle: the arrival velocity carries straight into a
// damped spring — no speed cut at the handoff. The stiff spring catches
// the high-speed arrival in a short recoil (overshoot ≈ speed/omega)
// before easing back to rest.
const SETTLE_OMEGA: f32 = 0.8; // rad/frame
const SETTLE_ZETA: f32 = 0.55; // slight underdamping: tiny overshoot, decisive snap back
const SETTLE_DONE_DIST: f32 = 1.5; // × dpr
const SETTLE_DONE_SPEED: f32 = 0.2; // × dpr
const SETTLE_TIMEOUT_SEC: f32 = 1.5;
const HEART_MIN_SIZE_SCALE: f32 = 0.38;

// Spawn bursts (initial calendar sync) beyond this budget skip the fly-in
// and fade in directly at their destinations, so a full day's events does
// not turn the canvas into a meteor storm. Spawns within the window count
// as one batch; single event additions always fly in.
const MAX_FLY_IN_HEARTS: usize = 3;
const SPAWN_BATCH_WINDOW_SEC: f32 = 1.0;

// Cold-start syncs push the whole day's events at once; spawn_heart only
// enqueues, and the update loop drains this many per frame so the UI
// never freezes — thousands of arrivals pour in over a couple of seconds.
const SYNC_DRAIN_PER_FRAME: usize = 24;

// Tagged hearts are capped at the visual comfort capacity of the canvas:
// past the cap, the oldest landed heart fades out and its event retires
// to the archive — the present stays readable, the past is not lost.
const MAX_TAGGED_HEARTS: usize = 200;
const MAX_ARCHIVE: usize = 10_000;

// Memory replay: every few minutes a small wave of archived events flies
// back in as dimmer, smaller ghosts. Waves are sparse on purpose —
// reminiscing is taxing. Each new wave gently fades the previous one.
const REPLAY_INTERVAL_MIN_SEC: f32 = 150.0;
const REPLAY_INTERVAL_MAX_SEC: f32 = 300.0;
const REPLAY_WAVE_MIN: usize = 4;
const REPLAY_WAVE_MAX: usize = 8;
const REPLAY_ALPHA: f32 = 0.55;
const REPLAY_SIZE_SCALE: f32 = 0.55;

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

const IncomingState = enum { flying, settling };

const IncomingKind = enum { tagged, replay };

const IncomingHeart = struct {
    particle: *Particle,
    event_id: ?[]const u8,
    target_x: f32,
    target_y: f32,
    was_touching_contour: bool,
    state: IncomingState,
    settle_start_sec: f32,
    kind: IncomingKind,
    fly_v0: f32,
    path_len: f32,
    trail_carry: f32,
};

/// C ABI callback invoked when a tagged heart is tapped.
/// `event_id` is borrowed: valid only for the duration of the call.
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
    spawn_queue: std.ArrayList([]u8),
    spawn_queue_head: usize,
    cooling: HeartCooling,
    archive: ArchiveList,
    landed_order: std.ArrayList([]const u8),
    replay_wave: std.ArrayList(*Particle),
    next_replay_sec: f32,
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
            .spawn_queue = .empty,
            .spawn_queue_head = 0,
            .cooling = HeartCooling.init(allocator),
            .archive = ArchiveList.init(allocator, MAX_ARCHIVE),
            .landed_order = .empty,
            .replay_wave = .empty,
            .next_replay_sec = 0.0,
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
        for (self.spawn_queue.items[self.spawn_queue_head..]) |id| {
            self.allocator.free(id);
        }
        self.spawn_queue.deinit(self.allocator);
        for (self.incoming_hearts.items) |cm| {
            if (cm.event_id) |id| self.allocator.free(id);
        }
        self.incoming_hearts.deinit(self.allocator);
        self.cooling.deinit();
        self.archive.deinit();
        self.landed_order.deinit(self.allocator);
        self.replay_wave.deinit(self.allocator);
        var key_it = self.tagged_hearts.keyIterator();
        while (key_it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.tagged_hearts.deinit();
        self.pool.deinit();
        self.gpu.deinit();
        self.allocator.destroy(self);
    }

    /// Frame-driven clock. All motion constants are per-frame tuned for
    /// 60fps; higher refresh rates speed the animation up proportionally.
    pub fn tick_elapsed(self: *Self) f32 {
        const elapsed = self.start_time;
        self.start_time += @as(f32, @floatCast(sapp.frameDuration()));
        self.last_elapsed = elapsed;
        return elapsed;
    }

    /// Frame-driven clock for C ABI callers, which have no elapsed time of
    /// their own (sokol only exposes a frame *duration*).
    pub fn current_elapsed(self: *Self) f32 {
        return self.last_elapsed;
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
        if (self.days_text_len > 0) {
            text_renderer.update_counter_layout(&self.heart, w, h, dpr, self.days_text_len, &self.text_layout);
        }

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
        self.drain_spawn_queue(elapsed);
        self.cooling.update(elapsed, &self.pool, &self.rng, dpr);
        self.update_counter_tap_pulse(elapsed);
        self.update_replay(elapsed);

        // Simulation step for every alive particle, exactly once per frame,
        // before compaction and rendering.
        for (self.pool.alive_slice()) |idx| {
            self.pool.get_particle(idx).update(elapsed, dpr);
        }
        self.pool.collect_alive();

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
                &self.days_text_buf,
                self.days_text_len,
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
    }

    pub fn handle_resize(self: *Self) void {
        self.resize_cooldown = 30;
        self.is_heart_ready = false;
        self.cooling.clear();

        // The upcoming HeartSystem.init resets the pool, orphaning every
        // particle pointer held in these containers — drop them now so a
        // later remove/update can never touch a recycled slot. Landed
        // hearts vanish with the pool, as they already did implicitly.
        // The archive owns plain strings and survives the reset.
        self.landed_order.clearRetainingCapacity();
        self.replay_wave.clearRetainingCapacity();
        var key_it = self.tagged_hearts.keyIterator();
        while (key_it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.tagged_hearts.clearRetainingCapacity();
        for (self.incoming_hearts.items) |cm| {
            if (cm.event_id) |id| self.allocator.free(id);
        }
        self.incoming_hearts.clearRetainingCapacity();
        if (self.is_meteor_ready) {
            self.meteor.reset();
        }
    }

    /// O(1) enqueue: cold-start syncs push thousands of events; the drain
    /// spreads spawn work across frames so the UI never freezes.
    /// `event_id` is borrowed; the queue owns a sentinel-terminated copy
    /// (tagged-heart keys are cast to C strings for the tap callback).
    pub fn spawn_heart(self: *Self, event_id: []const u8, elapsed: f32) !void {
        _ = elapsed;
        const id_dup = try self.allocator.allocSentinel(u8, event_id.len, 0);
        @memcpy(id_dup[0..event_id.len], event_id);
        errdefer self.allocator.free(id_dup);
        try self.spawn_queue.append(self.allocator, id_dup);
    }

    fn drain_spawn_queue(self: *Self, elapsed: f32) void {
        var budget: usize = SYNC_DRAIN_PER_FRAME;
        while (budget > 0 and self.spawn_queue_head < self.spawn_queue.items.len) : (budget -= 1) {
            const id = self.spawn_queue.items[self.spawn_queue_head];
            self.spawn_queue_head += 1;
            self.do_spawn_heart(id, elapsed);
        }
        if (self.spawn_queue_head == self.spawn_queue.items.len) {
            self.spawn_queue.clearRetainingCapacity();
            self.spawn_queue_head = 0;
        }
    }

    /// Spawn one queued event. Takes ownership of `id`.
    fn do_spawn_heart(self: *Self, id: []u8, elapsed: f32) void {
        const dpr = self.dpr;
        const w = sapp.widthf();
        const h = sapp.heightf();

        if (self.tagged_hearts.contains(id)) {
            self.allocator.free(id);
            return;
        }
        for (self.incoming_hearts.items) |cm| {
            if (cm.event_id) |cm_id| {
                if (std.mem.eql(u8, cm_id, id)) {
                    self.allocator.free(id);
                    return;
                }
            }
        }

        // Re-adding an archived event brings it back to the present.
        _ = self.archive.remove(id);

        const dest = self.pick_landing_spot(w, h, dpr);

        // Batch tracking on the frame-driven clock: bursts within the
        // window count as one batch (initial calendar sync); single event
        // additions always fly in.
        const now = self.last_elapsed;
        if (now - self.last_spawn_sec > SPAWN_BATCH_WINDOW_SEC) {
            self.spawn_batch_count = 0;
        }
        self.last_spawn_sec = now;
        self.spawn_batch_count += 1;

        if (self.spawn_batch_count > MAX_FLY_IN_HEARTS) {
            self.convert_incoming_to_fade_in(now);
            self.spawn_heart_fade_in(id, dest.x, dest.y, now);
            return;
        }

        self.spawn_fly_in(.tagged, id, dest, w, h, dpr, elapsed) catch {
            log.warn("spawn_fly_in failed, discarding heart for event_id", .{});
            self.allocator.free(id);
        };
    }

    /// Launch a meteor heart towards `dest` on the shared ease-out
    /// trajectory. For `.tagged`, `event_id` ownership moves into the
    /// incoming list; for `.replay` it must be null.
    fn spawn_fly_in(self: *Self, kind: IncomingKind, event_id: ?[]const u8, dest: Vec2, w: f32, h: f32, dpr: f32, elapsed: f32) !void {
        const speed = FLY_START_SPEED * dpr;
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
            .event_id = event_id,
            .target_x = dest.x,
            .target_y = dest.y,
            .was_touching_contour = false,
            .state = .flying,
            .settle_start_sec = 0.0,
            .kind = kind,
            .fly_v0 = speed,
            .path_len = t * speed,
            .trail_carry = 0.0,
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
            return;
        };
        self.track_landed(event_id);
    }

    /// Record a landing for cap enforcement: the oldest heart past the cap
    /// fades out and its event retires to the archive.
    fn track_landed(self: *Self, event_id: []const u8) void {
        self.landed_order.append(self.allocator, event_id) catch {
            log.warn("landed_order.append failed, heart will not age out", .{});
        };
        while (self.tagged_hearts.count() > MAX_TAGGED_HEARTS and self.landed_order.items.len > 0) {
            const oldest_id = self.landed_order.orderedRemove(0);
            const kv = self.tagged_hearts.fetchRemove(oldest_id) orelse continue;
            kv.value.set_fading_out(true);
            self.cooling.cancel(oldest_id);
            self.archive.put(kv.key) catch {
                log.warn("archive.put failed, dropping archived event_id", .{});
            };
        }
    }

    fn convert_incoming_to_fade_in(self: *Self, elapsed: f32) void {
        var i: usize = 0;
        while (i < self.incoming_hearts.items.len) {
            const cm = self.incoming_hearts.items[i];
            // Replay hearts are not part of the batch budget: they keep
            // flying while tagged arrivals convert to fade-in.
            if (cm.kind != .tagged) {
                i += 1;
                continue;
            }
            self.fade_in_heart_at(cm.particle, cm.event_id.?, cm.target_x, cm.target_y, elapsed);
            _ = self.incoming_hearts.swapRemove(i);
        }
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
            for (self.landed_order.items, 0..) |id, i| {
                if (std.mem.eql(u8, id, event_id)) {
                    _ = self.landed_order.orderedRemove(i);
                    break;
                }
            }
        }
        _ = self.archive.remove(event_id);
    }

    pub fn sync_hearts(self: *Self, active_ids: [:0]const u8) void {
        var active_set = std.StringHashMap(void).init(self.allocator);
        defer active_set.deinit();

        var split_iter = std.mem.splitScalar(u8, active_ids, '\n');
        while (split_iter.next()) |id| {
            if (id.len > 0) {
                active_set.put(id, {}) catch {
                    log.warn("active_set.put failed, skipping id", .{});
                    continue;
                };
            }
        }

        var stale_ids: std.ArrayList([]const u8) = .empty;
        defer stale_ids.deinit(self.allocator);

        var heart_it = self.tagged_hearts.iterator();
        while (heart_it.next()) |entry| {
            if (!active_set.contains(entry.key_ptr.*)) {
                stale_ids.append(self.allocator, entry.key_ptr.*) catch {
                    log.warn("stale_ids.append failed, skipping id", .{});
                    continue;
                };
            }
        }

        for (stale_ids.items) |id| {
            self.remove_heart(id);
        }

        var mi: usize = 0;
        while (mi < self.incoming_hearts.items.len) {
            const cm = self.incoming_hearts.items[mi];
            if (cm.kind == .tagged and !active_set.contains(cm.event_id.?)) {
                cm.particle.set_alive(false);
                self.allocator.free(cm.event_id.?);
                _ = self.incoming_hearts.swapRemove(mi);
            } else {
                mi += 1;
            }
        }

        // Queued spawns for events that vanished are dropped too.
        var qr: usize = self.spawn_queue_head;
        var qw: usize = self.spawn_queue_head;
        while (qr < self.spawn_queue.items.len) : (qr += 1) {
            const id = self.spawn_queue.items[qr];
            if (active_set.contains(id)) {
                self.spawn_queue.items[qw] = id;
                qw += 1;
            } else {
                self.allocator.free(id);
            }
        }
        self.spawn_queue.shrinkRetainingCapacity(qw);

        self.archive.retain_only(&active_set);
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
                // Keys are sentinel-allocated in spawn_heart, so this cast
                // to a C string pointer is sound for the tap callback.
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
            diff_days = (platform_time.unix_ms() - self.days_counter_start_ms) / (1000.0 * 60.0 * 60.0 * 24.0);
        }
        self.days_text_len = days_fmt.format_days(&self.days_text_buf, diff_days);
    }

    /// Memory replay scheduler: sparse waves only — reminiscing is taxing.
    fn update_replay(self: *Self, elapsed: f32) void {
        if (self.archive.len() == 0) return;
        if (self.next_replay_sec == 0.0) {
            self.next_replay_sec = elapsed + self.rng.random_range(REPLAY_INTERVAL_MIN_SEC, REPLAY_INTERVAL_MAX_SEC);
            return;
        }
        if (elapsed < self.next_replay_sec) return;
        self.next_replay_sec = elapsed + self.rng.random_range(REPLAY_INTERVAL_MIN_SEC, REPLAY_INTERVAL_MAX_SEC);
        self.spawn_replay_wave(elapsed);
    }

    /// A wave of memories: the previous wave fades out as the new one
    /// flies in, each heart on the shared ease-out trajectory.
    fn spawn_replay_wave(self: *Self, elapsed: f32) void {
        for (self.replay_wave.items) |p| {
            if (p.is_alive()) p.set_fading_out(true);
        }
        self.replay_wave.clearRetainingCapacity();

        var indices: [REPLAY_WAVE_MAX]usize = undefined;
        const want = REPLAY_WAVE_MIN + self.rng.random_index(REPLAY_WAVE_MAX - REPLAY_WAVE_MIN + 1);
        const count = self.archive.sample_indices(want, &self.rng, &indices);

        const dpr = self.dpr;
        const w = sapp.widthf();
        const h = sapp.heightf();
        for (indices[0..count]) |_| {
            const dest = self.pick_landing_spot(w, h, dpr);
            self.spawn_fly_in(.replay, null, dest, w, h, dpr, elapsed) catch |err| {
                log.warn("replay fly-in failed: {}", .{err});
                return;
            };
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
            const cm = &self.incoming_hearts.items[i];
            const p = cm.particle;
            if (!p.is_alive()) {
                if (cm.event_id) |id| self.allocator.free(id);
                _ = self.incoming_hearts.swapRemove(i);
                continue;
            }

            const prev_x = p.pos_x();
            const prev_y = p.pos_y();
            move_incoming_heart(cm);
            self.lay_incoming_trail(cm, prev_x, prev_y, elapsed, dpr);
            if (self.check_incoming_landing(cm, i, elapsed, dpr)) continue;

            i += 1;
        }
    }

    /// Evenly spaced trail dots along the whole path: the sub-gap
    /// remainder carries across frames, so dot spacing never jitters
    /// as the speed changes.
    fn lay_incoming_trail(self: *Self, cm: *IncomingHeart, prev_x: f32, prev_y: f32, elapsed: f32, dpr: f32) void {
        const p = cm.particle;
        const step_x = p.pos_x() - prev_x;
        const step_y = p.pos_y() - prev_y;
        const step_dist = @sqrt(step_x * step_x + step_y * step_y);
        if (step_dist == 0.0) return;

        const gap = TRAIL_GAP * dpr;
        cm.trail_carry += step_dist;
        while (cm.trail_carry >= gap) {
            cm.trail_carry -= gap;
            const f = 1.0 - cm.trail_carry / step_dist;
            const trail = self.pool.alloc_particle(
                Vec2{ .x = prev_x + step_x * f, .y = prev_y + step_y * f },
                elapsed,
                .{ .size = meteor_sys.TRAIL_SIZE * dpr },
                &self.rng,
            );
            trail.set_vel(0, 0);
            trail.set_acc(0, 0);
            trail.set_lifespan(meteor_sys.TRAIL_LIFESPAN);
        }
    }

    /// Contour showers, flying→settling handoff, and landing detection.
    /// Returns true when the heart transitioned (item `index` removed).
    fn check_incoming_landing(self: *Self, cm: *IncomingHeart, index: usize, elapsed: f32, dpr: f32) bool {
        const p = cm.particle;
        const adx = cm.target_x - p.pos_x();
        const ady = cm.target_y - p.pos_y();
        const dist = @sqrt(adx * adx + ady * ady);

        switch (cm.state) {
            .flying => {
                // Each fresh contact with the big heart's contour fires one
                // meteor shower travelling parallel to this heart's own
                // trajectory, towards the same destination. Slower and
                // dimmer than the heart so it stays visibly in the lead.
                const touching = self.heart.touches_contour(p.pos_x(), p.pos_y(), p.get_size());
                if (touching and !cm.was_touching_contour) {
                    self.meteor_from_heart(p.vel_x(), p.vel_y(), .{
                        .force = true,
                        .opacity = 0.65,
                        .speed_scale = 0.6,
                    });
                }
                cm.was_touching_contour = touching;

                const past_target = (p.vel_x() * adx + p.vel_y() * ady) < 0;
                if (dist < 20.0 * dpr or past_target) {
                    // Hand the arrival velocity straight to the spring —
                    // no speed cut, so the braking continues seamlessly
                    // through the follow-through overshoot.
                    cm.state = .settling;
                    cm.settle_start_sec = elapsed;
                }
            },
            .settling => {
                const speed = @sqrt(p.vel_x() * p.vel_x() + p.vel_y() * p.vel_y());
                const timed_out = elapsed - cm.settle_start_sec > SETTLE_TIMEOUT_SEC;
                if ((dist < SETTLE_DONE_DIST * dpr and speed < SETTLE_DONE_SPEED * dpr) or timed_out) {
                    self.transition_incoming_heart(index, elapsed);
                    return true;
                }
            },
        }
        return false;
    }

    fn transition_incoming_heart(self: *Self, index: usize, elapsed: f32) void {
        const cm = self.incoming_hearts.items[index];
        const p = cm.particle;

        p.set_pos(cm.target_x, cm.target_y);
        p.set_immortal(false);
        p.set_meteor(false);
        p.set_floating(true);
        p.set_beat(true);
        p.set_lifespan(self.rng.random_range(75.0, 110.0));
        p.set_birth_sec(elapsed);
        p.set_size(MAX_PARTICLE_SIZE * self.dpr);
        p.set_vel(
            self.rng.random_range(-0.5, 0.5) * self.dpr,
            self.rng.random_range(-2.5, -1.5) * self.dpr,
        );

        if (cm.kind == .replay) {
            // A memory, not a resident: dimmer and smaller than a real
            // heart, untracked, unfading until the next wave replaces it.
            p.set_size_scale(REPLAY_SIZE_SCALE * self.rng.random_range(0.9, 1.1));
            p.set_alpha_scale(REPLAY_ALPHA);
            self.replay_wave.append(self.allocator, p) catch {
                log.warn("replay_wave.append failed, discarding replay heart", .{});
                p.set_alive(false);
            };
            _ = self.incoming_hearts.swapRemove(index);
            return;
        }

        const event_id = cm.event_id.?;
        p.set_size_scale(self.rng.random_range(0.8, 1.0));

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
        self.track_landed(event_id);
    }
};

fn move_incoming_heart(cm: *IncomingHeart) void {
    const p = cm.particle;
    switch (cm.state) {
        .flying => {
            // Ease-out braking: speed follows v0·(remaining/path)^((n-1)/n),
            // a pure function of the remaining distance. Scaling both
            // components equally keeps the trajectory a straight line.
            const rdx = cm.target_x - p.pos_x();
            const rdy = cm.target_y - p.pos_y();
            const remaining = @sqrt(rdx * rdx + rdy * rdy);
            const sp = @sqrt(p.vel_x() * p.vel_x() + p.vel_y() * p.vel_y());
            const nsp = core_math.ease_out_speed(cm.fly_v0, remaining, cm.path_len, FLY_EASE_POWER, FLY_CRUISE_FRAC);
            const ratio = nsp / sp;
            p.set_vel(p.vel_x() * ratio, p.vel_y() * ratio);
            p.translate_by_vel();
        },
        .settling => {
            const s = core_math.spring_step(p.pos_x(), p.pos_y(), p.vel_x(), p.vel_y(), cm.target_x, cm.target_y, SETTLE_OMEGA, SETTLE_ZETA);
            p.set_pos(s.x, s.y);
            p.set_vel(s.vx, s.vy);
        },
    }
}
