const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const slog = sokol.log;
const shd = @import("shaders/particle.glsl.zig");

const business = @import("core/business.zig");
const particle = @import("Particle.zig");
const HeartSystem = @import("HeartSystem.zig");
const MeteorSystem = @import("MeteorSystem.zig");
const Rgba = business.Rgba;

const MAX_PARTICLES = 5000;
const MAX_INSTANCES = MAX_PARTICLES * 2; // stroke + fill per particle
const STROKE_WIDTH: f32 = 2.0;

const GpuInstance = extern struct {
    pos_x: f32,
    pos_y: f32,
    size: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
    shape: f32,
};

const GpuState = struct {
    pass_action: sg.PassAction = .{},
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
    instance_buf: [MAX_INSTANCES]GpuInstance = undefined,
    instance_count: u32 = 0,

    // Physics state
    heart: HeartSystem.HeartSystem = undefined,
    heart_ready: bool = false,
    meteor: MeteorSystem.MeteorSystem = undefined,
    meteor_ready: bool = false,
    transition_start: f32 = 0.0,
    resize_cooldown: u32 = 0,
    dpr: f32 = 1.0,
    start_time: f32 = 0.0,

    // Day counter
    days_text_buf: [32]u8 = undefined,
    days_text_len: usize = 0,
};

var gs: GpuState = .{};

// Orthographic projection: pixel coords → NDC
fn ortho(left: f32, right: f32, bottom: f32, top: f32) [16]f32 {
    return .{
        2.0 / (right - left),             0.0,                              0.0,  0.0,
        0.0,                              2.0 / (top - bottom),             0.0,  0.0,
        0.0,                              0.0,                              -1.0, 0.0,
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), 0.0,  1.0,
    };
}

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    gs.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 169.0 / 255.0, .g = 229.0 / 255.0, .b = 214.0 / 255.0, .a = 1.0 },
    };

    // Static quad geometry: 4 corners, 6 indices → 2 triangles
    gs.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&[_]f32{
            0.0, 0.0, // bottom-left
            1.0, 0.0, // bottom-right
            0.0, 1.0, // top-left
            1.0, 1.0, // top-right
        }),
    });

    gs.bind.index_buffer = sg.makeBuffer(.{
        .usage = .{ .index_buffer = true },
        .data = sg.asRange(&[_]u16{ 0, 1, 2, 1, 3, 2 }),
    });

    // Dynamic instance buffer
    gs.bind.vertex_buffers[1] = sg.makeBuffer(.{
        .usage = .{ .stream_update = true },
        .size = MAX_INSTANCES * @sizeOf(GpuInstance),
    });

    // Pipeline with instancing and alpha blending
    // iOS simulator reports .METAL_SIMULATOR, but the shader source is identical to .METAL_IOS.
    var backend = sg.queryBackend();
    if (backend == .METAL_SIMULATOR) {
        backend = .METAL_IOS;
    }
    gs.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.particleShaderDesc(backend)),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            // Vertex buffer 0: quad corners
            l.attrs[shd.ATTR_particle_quad_corner] = .{ .format = .FLOAT2, .buffer_index = 0 };
            // Vertex buffer 1: per-instance data
            l.buffers[1].step_func = .PER_INSTANCE;
            l.buffers[1].step_rate = 1;
            l.attrs[shd.ATTR_particle_inst_pos] = .{ .format = .FLOAT2, .offset = 0, .buffer_index = 1 };
            l.attrs[shd.ATTR_particle_inst_size] = .{ .format = .FLOAT, .offset = 8, .buffer_index = 1 };
            l.attrs[shd.ATTR_particle_inst_color] = .{ .format = .FLOAT4, .offset = 12, .buffer_index = 1 };
            l.attrs[shd.ATTR_particle_inst_shape] = .{ .format = .FLOAT, .offset = 28, .buffer_index = 1 };
            break :init l;
        },
        .index_type = .UINT16,
        .colors = init: {
            var c: [8]sg.ColorTargetState = @splat(.{});
            c[0] = .{
                .blend = .{
                    .enabled = true,
                    .src_factor_rgb = .SRC_ALPHA,
                    .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                    .op_rgb = .ADD,
                    .src_factor_alpha = .ONE,
                    .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
                    .op_alpha = .ADD,
                },
            };
            break :init c;
        },
    });

    gs.dpr = sapp.dpiScale();
    gs.start_time = @floatCast(sapp.frameDuration()); // will accumulate in frame()
}

export fn frame() void {
    const elapsed = gs.start_time;
    gs.start_time += @as(f32, @floatCast(sapp.frameDuration()));

    const w: f32 = sapp.widthf();
    const h: f32 = sapp.heightf();
    const dpr = sapp.dpiScale();

    // Resize detection
    if (gs.resize_cooldown > 0) {
        gs.resize_cooldown -= 1;
    } else if (!gs.heart_ready) {
        initSystems(w, h, dpr, elapsed);
    }

    // Physics + GPU buffer fill
    if (gs.heart_ready and gs.resize_cooldown == 0) {
        updateAndFillBuffers(w, h, elapsed, dpr);
    }

    // Upload instance data
    sg.updateBuffer(gs.bind.vertex_buffers[1], sg.asRange(gs.instance_buf[0..gs.instance_count]));

    // Compute MVP
    const mvp = ortho(0, w, h, 0);
    const vs_params = shd.VsParams{ .mvp = mvp };

    // Render
    sg.beginPass(.{ .action = gs.pass_action, .swapchain = sglue.swapchain() });
    if (gs.instance_count > 0) {
        sg.applyPipeline(gs.pip);
        sg.applyBindings(gs.bind);
        sg.applyUniforms(shd.UB_vs_params, sg.asRange(&vs_params));
        sg.draw(0, 6, @intCast(gs.instance_count));
    }

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    sg.shutdown();
}

fn initSystems(w: f32, h: f32, dpr: f32, elapsed: f32) void {
    gs.dpr = dpr;
    const hx: f32 = w / 2.0 - 50.0 * dpr;
    const hy: f32 = h / 2.0 - 200.0 * dpr;
    const fp_x: f32 = w / 2.0 - 50.0 * dpr; // approximate: will be recalculated in frame
    const fp_y: f32 = h - 80.0 * dpr;

    gs.heart = HeartSystem.HeartSystem.init(elapsed, hx, hy, h, fp_x, fp_y, dpr);
    gs.heart_ready = true;
    gs.transition_start = elapsed;

    if (!gs.meteor_ready) {
        gs.meteor = MeteorSystem.MeteorSystem.init(w, h, dpr);
        gs.meteor_ready = true;
    }
}

fn updateAndFillBuffers(w: f32, h: f32, elapsed: f32, dpr: f32) void {
    const t: f32 = @min(1.0, (elapsed - gs.transition_start) / 3.0);

    // Day counter text
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
    const unix_ms: f64 = @as(f64, @floatFromInt(ts.sec)) * 1000.0 + @as(f64, @floatFromInt(ts.nsec)) / 1_000_000.0;
    const start_ms: f64 = 1660694400000.0;
    const diff_days = (unix_ms - start_ms) / (1000.0 * 60.0 * 60.0 * 24.0);
    const int_part: u64 = @intFromFloat(@floor(diff_days));
    const frac: f64 = diff_days - @floor(diff_days);
    gs.days_text_len = 0;
    formatUint(int_part);
    if (gs.days_text_len < gs.days_text_buf.len) {
        gs.days_text_buf[gs.days_text_len] = '.';
        gs.days_text_len += 1;
    }
    var f = frac;
    var digits: usize = 0;
    while (digits < 10) : (digits += 1) {
        f *= 10.0;
        const d: u8 = @intFromFloat(@floor(f));
        f -= @floor(f);
        if (gs.days_text_len < gs.days_text_buf.len) {
            gs.days_text_buf[gs.days_text_len] = '0' + d;
            gs.days_text_len += 1;
        }
    }
    const suffix = " DAYS";
    for (suffix) |byte| {
        if (gs.days_text_len < gs.days_text_buf.len) {
            gs.days_text_buf[gs.days_text_len] = byte;
            gs.days_text_len += 1;
        }
    }
    // Null-terminate for sokol_debugtext.puts (expects [:0]const u8).
    if (gs.days_text_len < gs.days_text_buf.len) {
        gs.days_text_buf[gs.days_text_len] = 0;
    }

    // Physics
    gs.heart.update(elapsed);
    particle.collectAlive();
    if (gs.meteor_ready) {
        gs.meteor.update();
    }

    // Fill GPU instance buffer
    const stroke_width: f32 = STROKE_WIDTH * dpr;
    const radius_margin: f32 = stroke_width + 3.0;
    const alive = particle.alive_indices[0..particle.alive_count];
    var inst_count: u32 = 0;
    const cap = MAX_INSTANCES;

    for (alive) |idx| {
        const p = &particle.particle_pool[idx];

        const max_alpha: f32 = if (p.immortal) 1.0 else business.scale(p.lifespan, particle.MAX_LIFESPAN, 200.0) / 255.0;
        const display_size: f32 = business.scale(p.lifespan, particle.MAX_LIFESPAN, p.size);

        // Off-screen culling
        const radius: f32 = display_size + radius_margin;
        if (p.pos.x + radius < 0.0 or p.pos.x - radius >= w or
            p.pos.y + radius < 0.0 or p.pos.y - radius >= h) continue;

        const fill_radius = display_size;
        const fill_alpha = max_alpha * t;
        const stroke_radius = display_size + stroke_width;
        const stroke_alpha = @min(1.0, p.lifespan / 255.0) * t;

        const fill_shape: f32 = if (display_size < 8.0) 0.0 else 1.0;
        const stroke_shape: f32 = if (display_size + stroke_width < 8.0) 0.0 else 1.0;

        // Stroke (drawn first, behind fill)
        if (stroke_alpha > 10.0 / 255.0 and inst_count < cap) {
            const sc = Rgba.heart_stroke;
            gs.instance_buf[inst_count] = .{
                .pos_x = p.pos.x,
                .pos_y = p.pos.y,
                .size = stroke_radius,
                .r = @as(f32, @floatFromInt(sc.r)) / 255.0,
                .g = @as(f32, @floatFromInt(sc.g)) / 255.0,
                .b = @as(f32, @floatFromInt(sc.b)) / 255.0,
                .a = stroke_alpha,
                .shape = stroke_shape,
            };
            inst_count += 1;
        }

        // Fill (drawn second, on top)
        if (fill_alpha > 0.0 and inst_count < cap) {
            const fc = Rgba.heart_fill;
            gs.instance_buf[inst_count] = .{
                .pos_x = p.pos.x,
                .pos_y = p.pos.y,
                .size = fill_radius,
                .r = @as(f32, @floatFromInt(fc.r)) / 255.0,
                .g = @as(f32, @floatFromInt(fc.g)) / 255.0,
                .b = @as(f32, @floatFromInt(fc.b)) / 255.0,
                .a = fill_alpha,
                .shape = fill_shape,
            };
            inst_count += 1;
        }
    }
    // Text overlay: emit filled-square instances for the day counter.
    // Uses the 3×5 bitmap font from business.FONT_3X5.
    if (gs.days_text_len > 0) {
        inst_count = fillTextInstances(w, h, dpr, inst_count, cap);
    }

    gs.instance_count = inst_count;
}

fn fillTextInstances(w: f32, h: f32, dpr: f32, start_inst: u32, cap: u32) u32 {
    const pixel_size: f32 = @max(1.0, dpr); // font pixel radius; each pixel = 2*dpr on screen, matching main-branch text_scale
    const char_stride: f32 = pixel_size * 2.0 * 3.0 + pixel_size; // 3 cols × diameter + 1 gap
    const gap: f32 = 4.0 * dpr;
    const max_hr: f32 = (particle.MAX_PARTICLE_SIZE + 4.0) * dpr;

    // Compute text width first so we know the full group extent.
    const text_width: f32 = @as(f32, @floatFromInt(gs.days_text_len)) * char_stride;

    // Float-heart area width: spread between the two hearts + radius margins.
    const hearts_area_w: f32 = 7.0 * dpr + 2.0 * max_hr;
    const group_w: f32 = hearts_area_w + gap + text_width;
    const group_left: f32 = w / 2.0 - group_w / 2.0;

    // Reposition the float-heart pair to the centered group origin.
    const left_h = gs.heart.float_pair[0];
    const right_h = gs.heart.float_pair[1];
    const dx: f32 = (group_left + max_hr) - left_h.pos.x;
    left_h.pos.x += dx;
    right_h.pos.x += dx;
    left_h.pos.y = h - 80.0 * dpr;
    right_h.pos.y = h - 80.0 * dpr - 2.0 * dpr;

    // Text starts after the hearts area + gap.
    const text_x: f32 = group_left + hearts_area_w + gap;
    const text_y: f32 = h - 83.0 * dpr;

    var inst_count = start_inst;

    const color = Rgba.white;
    const r: f32 = @as(f32, @floatFromInt(color.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(color.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(color.b)) / 255.0;

    for (gs.days_text_buf[0..gs.days_text_len], 0..) |ch, ci| {
        const char_idx = business.charIndex(ch);
        if (char_idx >= business.FONT_3X5.len) continue;
        const glyph = business.FONT_3X5[char_idx];

        const cx: f32 = text_x + @as(f32, @floatFromInt(ci)) * char_stride;

        var row: usize = 0;
        while (row < 5) : (row += 1) {
            const bits = glyph[row];
            var col: usize = 0;
            while (col < 3) : (col += 1) {
                if ((bits >> @as(u3, @intCast(2 - col))) & 1 == 0) {
                    continue;
                }
                if (inst_count >= cap) return inst_count;

                gs.instance_buf[inst_count] = .{
                    .pos_x = cx + @as(f32, @floatFromInt(col)) * pixel_size * 2.0 + pixel_size,
                    .pos_y = text_y + @as(f32, @floatFromInt(row)) * pixel_size * 2.0 + pixel_size,
                    .size = pixel_size,
                    .r = r,
                    .g = g,
                    .b = b,
                    .a = 1.0,
                    .shape = 2.0, // filled square
                };
                inst_count += 1;
            }
        }
    }

    return inst_count;
}

fn formatUint(n: u64) void {
    if (n == 0) {
        if (gs.days_text_len < gs.days_text_buf.len) {
            gs.days_text_buf[gs.days_text_len] = '0';
            gs.days_text_len += 1;
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
        if (gs.days_text_len < gs.days_text_buf.len) {
            gs.days_text_buf[gs.days_text_len] = tmp[j];
            gs.days_text_len += 1;
        }
    }
}

// Event handling
export fn event(ev: [*c]const sapp.Event) void {
    switch (ev.*.type) {
        .TOUCHES_BEGAN => {
            if (gs.meteor_ready) {
                const t = ev.*.touches[0];
                gs.meteor.falling(t.pos_x, t.pos_y);
            }
        },
        .MOUSE_DOWN => {
            if (gs.meteor_ready) {
                gs.meteor.falling(ev.*.mouse_x, ev.*.mouse_y);
            }
        },
        .RESIZED => {
            gs.resize_cooldown = 30;
            gs.heart_ready = false;
        },
        else => {},
    }
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 800,
        .height = 600,
        .icon = .{ .sokol_default = true },
        .window_title = "oayao",
        .logger = .{ .func = slog.func },
        .high_dpi = true,
    });
}
