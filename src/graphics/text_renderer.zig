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

pub fn fill_text_instances(
    gpu: *GpuState,
    w: f32,
    h: f32,
    dpr: f32,
    days_text_buf: []const u8,
    days_text_len: usize,
    heart: *HeartSystem,
    start_inst: u32,
) u32 {
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
    const dx: f32 = (group_left + max_hr) - left_h.pos.x;
    left_h.pos.x += dx;
    right_h.pos.x += dx;
    left_h.pos.y = h - 80.0 * dpr;
    right_h.pos.y = h - 80.0 * dpr - 2.0 * dpr;

    const text_x: f32 = group_left + hearts_area_w + gap;
    const text_y: f32 = h - 83.0 * dpr;

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

pub fn fill_particle_instances(
    gpu: *GpuState,
    pool: *ParticlePool,
    w: f32,
    h: f32,
    dpr: f32,
    t: f32,
    start_inst: u32,
) u32 {
    const stroke_width: f32 = STROKE_WIDTH * dpr;
    const radius_margin: f32 = stroke_width + 3.0;
    const alive = pool.alive_slice();
    var inst_count = start_inst;
    const cap = MAX_INSTANCES;

    for (alive) |idx| {
        const p = pool.get_particle(idx);

        const max_alpha: f32 = if (p.is_immortal()) 1.0 else math.scale(p.lifespan, MAX_LIFESPAN, 200.0) / 255.0;
        const display_size: f32 = math.scale(p.lifespan, MAX_LIFESPAN, p.size);

        const radius: f32 = display_size + radius_margin;
        if (p.pos.x + radius < 0.0 or p.pos.x - radius >= w or
            p.pos.y + radius < 0.0 or p.pos.y - radius >= h) continue;

        if (inst_count >= cap) continue;

        const fill_alpha = max_alpha * t;
        const stroke_alpha = @min(1.0, p.lifespan / 255.0) * t;
        const shape: f32 = if (display_size + stroke_width < 8.0) 0.0 else 1.0;

        gpu.write_instance(inst_count, .{
            .pos_x = p.pos.x,
            .pos_y = p.pos.y,
            .stroke_size = display_size + stroke_width,
            .fill_size = display_size,
            .stroke_a = if (stroke_alpha > 10.0 / 255.0) stroke_alpha else 0.0,
            .fill_a = if (fill_alpha > 0.0) fill_alpha else 0.0,
            .shape = shape,
        });
        inst_count += 1;
    }

    return inst_count;
}
