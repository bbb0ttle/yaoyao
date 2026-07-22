//! Text and particle instance buffer filling for GPU upload.


const GpuInstance = @import("gpu_state.zig").GpuInstance;
const GpuState = @import("gpu_state.zig").GpuState;
const MAX_INSTANCES = @import("gpu_state.zig").MAX_INSTANCES;
const STROKE_WIDTH = @import("gpu_state.zig").STROKE_WIDTH;

const math = @import("../core/math.zig");
const font = @import("../core/font.zig");
const ParticlePool = @import("../particles/pool.zig").ParticlePool;
const HeartSystem = @import("../systems/heart_system.zig").HeartSystem;
const MAX_PARTICLE_SIZE = @import("../particles/particle.zig").MAX_PARTICLE_SIZE;
const MAX_LIFESPAN = @import("../particles/particle.zig").MAX_LIFESPAN;

/// Cached counter-text layout; recomputed only when inputs change
/// (text length grows over years; w/h change on resize).
pub const TextLayout = struct {
    w: f32 = 0,
    h: f32 = 0,
    dpr: f32 = 0,
    text_len: usize = 0,
    pixel_size: f32 = 0,
    char_stride: f32 = 0,
    text_x: f32 = 0,
    text_y: f32 = 0,

    fn matches(self: *const TextLayout, w: f32, h: f32, dpr: f32, text_len: usize) bool {
        return self.w == w and self.h == h and self.dpr == dpr and self.text_len == text_len;
    }
};

/// Recompute the cached counter-text layout and place the counter heart
/// pair — only when the inputs change. Called from the update phase so
/// the render fill below stays free of simulation side effects; between
/// layout changes the pair drifts freely.
pub fn update_counter_layout(
    heart: *HeartSystem,
    w: f32,
    h: f32,
    dpr: f32,
    days_text_len: usize,
    cache: *TextLayout,
) void {
    if (cache.matches(w, h, dpr, days_text_len)) return;

    const pixel_size: f32 = @max(1.0, dpr);
    const char_stride: f32 = pixel_size * 2.0 * 3.0 + pixel_size;
    const gap: f32 = 4.0 * dpr;
    const max_hr: f32 = (MAX_PARTICLE_SIZE + 4.0) * dpr;

    const text_width: f32 = @as(f32, @floatFromInt(days_text_len)) * char_stride;
    const hearts_area_w: f32 = 7.0 * dpr + 2.0 * max_hr;
    const group_w: f32 = hearts_area_w + gap + text_width;
    const group_left: f32 = w / 2.0 - group_w / 2.0;

    const left_h = heart.float_pair_left();
    const right_h = heart.float_pair_right();
    const dx: f32 = (group_left + max_hr) - left_h.pos_x();
    left_h.set_pos(left_h.pos_x() + dx, left_h.pos_y());
    right_h.set_pos(right_h.pos_x() + dx, right_h.pos_y());
    left_h.set_pos(left_h.pos_x(), h - 80.0 * dpr);
    right_h.set_pos(right_h.pos_x(), h - 80.0 * dpr - 2.0 * dpr);

    cache.* = .{
        .w = w,
        .h = h,
        .dpr = dpr,
        .text_len = days_text_len,
        .pixel_size = pixel_size,
        .char_stride = char_stride,
        .text_x = group_left + hearts_area_w + gap,
        .text_y = h - 83.0 * dpr,
    };
}

/// Fill GPU instance buffer with 3x5 bitmap text glyph instances.
/// The layout cache must be fresh — call update_counter_layout first.
pub fn fill_text_instances(
    gpu: *GpuState,
    days_text_buf: []const u8,
    days_text_len: usize,
    start_inst: u32,
    cache: *const TextLayout,
) u32 {

    const pixel_size = cache.pixel_size;
    const char_stride = cache.char_stride;
    const text_x = cache.text_x;
    const text_y = cache.text_y;

    var inst_count = start_inst;

    for (days_text_buf[0..days_text_len], 0..) |ch, ci| {
        const char_idx = font.char_index(ch);
        if (char_idx >= font.FONT_3X5.len) continue;
        const glyph = font.FONT_3X5[char_idx];

        const cx: f32 = text_x + @as(f32, @floatFromInt(ci)) * char_stride;

        var row: usize = 0;
        while (row < 5) : (row += 1) {
            const bits = glyph[row];
            var col: usize = 0;
            while (col < 3) : (col += 1) {
                if ((bits >> @as(u3, @intCast(2 - col))) & 1 == 0) {
                    continue;
                }
                if (inst_count >= MAX_INSTANCES) return inst_count;

                gpu.write_instance(inst_count, .{
                    .pos_x = cx + @as(f32, @floatFromInt(col)) * pixel_size * 2.0 + pixel_size,
                    .pos_y = text_y + @as(f32, @floatFromInt(row)) * pixel_size * 2.0 + pixel_size,
                    .stroke_size = pixel_size,
                    .fill_size = pixel_size,
                    .stroke_a = 0.0,
                    .fill_a = 1.0,
                    .shape = 2.0,
                });
                inst_count += 1;
            }
        }
    }

    return inst_count;
}

/// Fill GPU instances for all alive particles, in two draw-order passes:
/// cooling embers first so they draw behind the hearts that shed them.
/// Particles must already have been updated this frame by the caller.
pub fn fill_particle_instances(
    gpu: *GpuState,
    pool: *ParticlePool,
    w: f32,
    h: f32,
    dpr: f32,
    t: f32,
    start_inst: u32,
) u32 {
    const alive = pool.alive_slice();
    var inst_count = fill_pass(gpu, pool, alive, true, w, h, dpr, t, start_inst);
    inst_count = fill_pass(gpu, pool, alive, false, w, h, dpr, t, inst_count);
    return inst_count;
}

fn fill_pass(
    gpu: *GpuState,
    pool: *ParticlePool,
    alive: []const usize,
    cooling_pass: bool,
    w: f32,
    h: f32,
    dpr: f32,
    t: f32,
    start_inst: u32,
) u32 {
    const stroke_width: f32 = STROKE_WIDTH * dpr;
    const radius_margin: f32 = stroke_width + 3.0;
    var inst_count = start_inst;
    const cap = MAX_INSTANCES;

    for (alive) |idx| {
        const p = pool.get_particle(idx);
        if (p.is_cooling() != cooling_pass) continue;

        const alpha_scale = p.get_alpha_scale();
        const max_alpha: f32 = if (p.is_immortal()) 1.0 else math.scale(p.get_lifespan(), MAX_LIFESPAN, 200.0) / 255.0;
        const display_size: f32 = math.scale(p.get_lifespan(), MAX_LIFESPAN, p.get_size());

        const radius: f32 = display_size + radius_margin;
        if (p.pos_x() + radius < 0.0 or p.pos_x() - radius >= w or
            p.pos_y() + radius < 0.0 or p.pos_y() - radius >= h) continue;

        if (inst_count >= cap) continue;

        const fill_alpha = max_alpha * t * alpha_scale;
        const stroke_alpha = @min(1.0, p.get_lifespan() / 255.0) * t * alpha_scale;
        const shape: f32 = if (p.is_blob()) 3.0 else if (display_size + stroke_width < 8.0) 0.0 else 1.0;

        gpu.write_instance(inst_count, .{
            .pos_x = p.pos_x(),
            .pos_y = p.pos_y(),
            .stroke_size = display_size + stroke_width,
            .fill_size = display_size,
            .stroke_a = if (p.is_blob()) 0.0 else if (stroke_alpha > 10.0 / 255.0) stroke_alpha else 0.0,
            .fill_a = if (fill_alpha > 0.0) fill_alpha else 0.0,
            .shape = shape,
        });
        inst_count += 1;
    }

    return inst_count;
}
