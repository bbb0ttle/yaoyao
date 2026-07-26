//! GPU state management: pipeline, buffers, instanced rendering.

const std = @import("std");

const sokol = @import("sokol");
const sg = sokol.gfx;
const shd = @import("../shaders/particle.glsl.zig");
const backend = @import("../platform/backend.zig");
const Rgba = @import("../core/types.zig").Rgba;
const Theme = @import("../core/theme.zig").Theme;
const math = @import("../core/math.zig");
const Particle = @import("../particles/particle.zig").Particle;
const MAX_LIFESPAN = @import("../particles/particle.zig").MAX_LIFESPAN;

pub const MAX_INSTANCES: u32 = 10000;
pub const STROKE_WIDTH: f32 = 2.0;

/// Baked-cloud cache capacity: the largest sky field is lenticular with
/// 6 lenses + 6 accent clouds.
pub const MAX_SKY_BAKES: usize = 16;
pub const BAKED_CLOUD_SHAPE: f32 = 9.0;

/// One sky particle's baked cloud texture: rgb tint factor + raw alpha,
/// rendered once (theme color and breath are applied per frame at blit).
const SkyBake = struct {
    particle: *Particle,
    image: sg.Image,
    color_view: sg.View,
    tex_view: sg.View,
    inst_buf: sg.Buffer,
    stroke_size: f32,
    display_size: f32,
};

/// Per-frame blit request for one baked cloud (filled by text_renderer).
/// `offset` is the instance's byte offset in the cloud buffer, assigned by
/// render() before the pass begins (buffer updates are illegal in-pass).
pub const SkyDraw = struct {
    bake: usize,
    pos_x: f32,
    pos_y: f32,
    fill_a: f32,
    offset: i32 = 0,
};

/// GPU instance data: position, sizes, alpha, and shape selector.
pub const GpuInstance = extern struct {
    pos_x: f32,
    pos_y: f32,
    stroke_size: f32,
    fill_size: f32,
    stroke_a: f32,
    fill_a: f32,
    shape: f32,
};

/// GPU pipeline, buffers, and instanced drawing state for sokol.
pub const GpuState = struct {
    const Self = @This();

    pass_action: sg.PassAction,
    pip: sg.Pipeline,
    bind: sg.Bindings,
    instance_buffer: []GpuInstance,
    instance_count: u32,
    allocator: std.mem.Allocator,

    // Baked clouds: one render-target texture per sky particle, blitted
    // per frame instead of recomputing fbm per pixel.
    pip_noblend: sg.Pipeline,
    sampler: sg.Sampler,
    dummy_image: sg.Image,
    dummy_view: sg.View,
    cloud_inst_buf: sg.Buffer,
    sky_bakes: [MAX_SKY_BAKES]SkyBake,
    sky_bake_count: usize,
    sky_draws: [MAX_SKY_BAKES]SkyDraw,
    sky_draw_count: u32,
    is_gl: bool,

    // Per-frame invariants, recomputed only when inputs change.
    last_w: f32,
    last_h: f32,
    last_theme: ?Theme,
    vs_params: shd.VsParams,
    fs_params: shd.FsParams,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const instance_buffer = try allocator.alloc(GpuInstance, MAX_INSTANCES);

        sg.setup(.{
            .environment = @import("sokol").glue.environment(),
            .logger = .{ .func = @import("sokol").log.func },
        });

        var self = Self{
            .pass_action = .{},
            .pip = .{},
            .bind = .{},
            .instance_buffer = instance_buffer,
            .instance_count = 0,
            .allocator = allocator,
            .pip_noblend = .{},
            .sampler = .{},
            .dummy_image = .{},
            .dummy_view = .{},
            .cloud_inst_buf = .{},
            .sky_bakes = undefined,
            .sky_bake_count = 0,
            .sky_draws = undefined,
            .sky_draw_count = 0,
            .is_gl = false,
            .last_w = -1.0,
            .last_h = -1.0,
            .last_theme = null,
            .vs_params = undefined,
            .fs_params = undefined,
        };

        self.pass_action.colors[0] = .{
            .load_action = .CLEAR,
            .clear_value = .{ .r = 169.0 / 255.0, .g = 229.0 / 255.0, .b = 214.0 / 255.0, .a = 1.0 },
        };

        self.init_buffers();
        const gpu_backend = backend.detect_gpu_backend();
        self.is_gl = gpu_backend == .GLES3 or gpu_backend == .GLCORE;
        self.pip = build_pipeline(gpu_backend, true);
        self.pip_noblend = build_pipeline(gpu_backend, false);

        // Shared sampler + a 1×1 stand-in texture so the bind table is
        // always complete, even in passes that never sample.
        self.sampler = sg.makeSampler(.{
            .min_filter = .LINEAR,
            .mag_filter = .LINEAR,
            .wrap_u = .CLAMP_TO_EDGE,
            .wrap_v = .CLAMP_TO_EDGE,
        });
        self.dummy_image = sg.makeImage(.{
            .usage = .{ .immutable = true },
            .width = 1,
            .height = 1,
            .data = init: {
                var d = sg.ImageData{};
                d.mip_levels[0] = sg.asRange(&[_]u8{ 255, 255, 255, 255 });
                break :init d;
            },
        });
        self.dummy_view = sg.makeView(.{ .texture = .{ .image = self.dummy_image } });
        self.bind.views[shd.VIEW_cloud_tex] = self.dummy_view;
        self.bind.samplers[shd.SMP_cloud_smp] = self.sampler;

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.bake_begin();
        sg.destroyView(self.dummy_view);
        sg.destroyImage(self.dummy_image);
        sg.destroySampler(self.sampler);
        self.allocator.free(self.instance_buffer);
        sg.shutdown();
        self.* = undefined;
    }

    pub fn set_instance_count(self: *Self, count: u32) void {
        self.instance_count = count;
    }

    pub fn write_instance(self: *Self, idx: u32, inst: GpuInstance) void {
        if (idx < MAX_INSTANCES) {
            self.instance_buffer[idx] = inst;
        }
    }

    pub fn upload_instances(self: *Self) void {
        sg.updateBuffer(self.bind.vertex_buffers[1], sg.asRange(self.instance_buffer[0..self.instance_count]));
    }

    /// Destroy every baked cloud texture. Called before a sky rebuild
    /// (mode switch, resize) and at shutdown.
    pub fn bake_begin(self: *Self) void {
        for (self.sky_bakes[0..self.sky_bake_count]) |bake| {
            sg.destroyView(bake.color_view);
            sg.destroyView(bake.tex_view);
            sg.destroyImage(bake.image);
            sg.destroyBuffer(bake.inst_buf);
        }
        self.sky_bake_count = 0;
    }

    /// Bake one sky particle's cloud pattern into its own texture — the
    /// noise cost is paid exactly once here instead of per pixel per frame.
    /// The bake is theme-agnostic (white fill; lenticular keeps its static
    /// iridescence in rgb) so theme transitions never trigger a rebake.
    pub fn bake_cloud(self: *Self, p: *Particle, dpr: f32) void {
        if (self.sky_bake_count >= MAX_SKY_BAKES) return;

        const display_size = math.scale(p.get_lifespan(), MAX_LIFESPAN, p.get_size());
        const stroke_size = display_size + STROKE_WIDTH * dpr;
        const px: i32 = @intFromFloat(@ceil(2.0 * stroke_size));

        const image = sg.makeImage(.{
            .usage = .{ .color_attachment = true },
            .width = px,
            .height = px,
            .pixel_format = .RGBA8,
        });
        const color_view = sg.makeView(.{ .color_attachment = .{ .image = image } });
        const tex_view = sg.makeView(.{ .texture = .{ .image = image } });

        // One-shot immutable instance buffer per bake: stream buffers
        // allow only a single updateBuffer per frame, and a sky rebuild
        // bakes up to 12 clouds in one frame.
        const inst: GpuInstance = .{
            .pos_x = stroke_size,
            .pos_y = stroke_size,
            .stroke_size = stroke_size,
            .fill_size = display_size,
            .stroke_a = p.get_birth_sec(),
            .fill_a = 1.0,
            .shape = 4.0 + @as(f32, @floatFromInt(@intFromEnum(p.get_sky_kind()) - 1)),
        };
        const inst_buf = sg.makeBuffer(.{ .data = sg.asRange(&inst) });

        const pxf: f32 = @floatFromInt(px);
        // GL samples textures bottom-up; flip the bake projection so the
        // sampled image matches Metal row-for-row.
        const mvp: [16]f32 = if (self.is_gl) ortho(0, pxf, 0, pxf) else ortho(0, pxf, pxf, 0);
        var fs: shd.FsParams = undefined;
        fs.fill_color = .{ 1.0, 1.0, 1.0, 1.0 };
        fs.stroke_color = .{ 1.0, 1.0, 1.0, 1.0 };
        fs.text_color = .{ 1.0, 1.0, 1.0, 1.0 };

        var action = sg.PassAction{};
        action.colors[0] = .{ .load_action = .CLEAR, .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 0 } };
        var attachments = sg.Attachments{};
        attachments.colors[0] = color_view;

        sg.beginPass(.{ .action = action, .attachments = attachments });
        sg.applyPipeline(self.pip_noblend);
        var bbind = self.bind;
        bbind.vertex_buffers[1] = inst_buf;
        sg.applyBindings(bbind);
        sg.applyUniforms(shd.UB_vs_params, sg.asRange(&mvp));
        sg.applyUniforms(shd.UB_fs_params, sg.asRange(&fs));
        sg.draw(0, 6, 1);
        sg.endPass();

        self.sky_bakes[self.sky_bake_count] = .{
            .particle = p,
            .image = image,
            .color_view = color_view,
            .tex_view = tex_view,
            .inst_buf = inst_buf,
            .stroke_size = stroke_size,
            .display_size = display_size,
        };
        self.sky_bake_count += 1;
    }

    pub fn find_bake(self: *const Self, p: *const Particle) ?usize {
        for (self.sky_bakes[0..self.sky_bake_count], 0..) |bake, i| {
            if (@intFromPtr(bake.particle) == @intFromPtr(p)) return i;
        }
        return null;
    }

    pub fn clear_sky_draws(self: *Self) void {
        self.sky_draw_count = 0;
    }

    pub fn push_sky_draw(self: *Self, draw: SkyDraw) void {
        if (self.sky_draw_count >= MAX_SKY_BAKES) return;
        self.sky_draws[self.sky_draw_count] = draw;
        self.sky_draw_count += 1;
    }

    pub fn render(self: *Self, w: f32, h: f32, theme: Theme) void {
        const dirty = self.last_w != w or self.last_h != h or
            self.last_theme == null or !std.meta.eql(self.last_theme.?, theme);
        if (dirty) {
            self.vs_params = .{ .mvp = ortho(0, w, h, 0) };
            self.fs_params = .{
                .fill_color = to_f32x4(theme.heart_fill),
                .stroke_color = to_f32x4(theme.heart_stroke),
                .text_color = to_f32x4(theme.timer_text),
            };
            self.pass_action.colors[0].clear_value = .{
                .r = @as(f32, @floatFromInt(theme.background.r)) / 255.0,
                .g = @as(f32, @floatFromInt(theme.background.g)) / 255.0,
                .b = @as(f32, @floatFromInt(theme.background.b)) / 255.0,
                .a = 1.0,
            };
            self.last_w = w;
            self.last_h = h;
            self.last_theme = theme;
        }

        const sglue = @import("sokol").glue;
        // Buffer updates are illegal inside a pass, so all cloud instances
        // are appended up front and only offset-referenced during the pass.
        for (self.sky_draws[0..self.sky_draw_count]) |*draw| {
            const bake = &self.sky_bakes[draw.bake];
            self.instance_buffer[0] = .{
                .pos_x = draw.pos_x,
                .pos_y = draw.pos_y,
                .stroke_size = bake.stroke_size,
                .fill_size = bake.display_size,
                .stroke_a = 0.0,
                .fill_a = draw.fill_a,
                .shape = BAKED_CLOUD_SHAPE,
            };
            draw.offset = sg.appendBuffer(self.cloud_inst_buf, sg.asRange(self.instance_buffer[0..1]));
        }

        sg.beginPass(.{ .action = self.pass_action, .swapchain = sglue.swapchain() });
        sg.applyPipeline(self.pip);
        sg.applyUniforms(shd.UB_vs_params, sg.asRange(&self.vs_params));
        sg.applyUniforms(shd.UB_fs_params, sg.asRange(&self.fs_params));
        // Baked clouds draw first (the sky is the backdrop); each blit is
        // one textured quad — no per-pixel noise work remains.
        if (self.sky_draw_count > 0) {
            for (self.sky_draws[0..self.sky_draw_count]) |draw| {
                if (draw.offset < 0) continue;
                const bake = &self.sky_bakes[draw.bake];
                var cbind = self.bind;
                cbind.vertex_buffers[1] = self.cloud_inst_buf;
                cbind.vertex_buffer_offsets[1] = draw.offset;
                cbind.views[shd.VIEW_cloud_tex] = bake.tex_view;
                cbind.samplers[shd.SMP_cloud_smp] = self.sampler;
                sg.applyBindings(cbind);
                sg.draw(0, 6, 1);
            }
        }
        if (self.instance_count > 0) {
            sg.applyBindings(self.bind);
            sg.draw(0, 6, @intCast(self.instance_count));
        }
        sg.endPass();
        sg.commit();
    }

    fn init_buffers(self: *Self) void {
        self.bind.vertex_buffers[0] = sg.makeBuffer(.{
            .data = sg.asRange(&[_]f32{
                0.0, 0.0,
                1.0, 0.0,
                0.0, 1.0,
                1.0, 1.0,
            }),
        });

        self.bind.index_buffer = sg.makeBuffer(.{
            .usage = .{ .index_buffer = true },
            .data = sg.asRange(&[_]u16{ 0, 1, 2, 1, 3, 2 }),
        });

        self.bind.vertex_buffers[1] = sg.makeBuffer(.{
            .usage = .{ .stream_update = true },
            .size = MAX_INSTANCES * @sizeOf(GpuInstance),
        });

        // Single-instance buffer for per-cloud blit draws (sokol cannot
        // offset the instance base portably, GLES3 lacks base_instance).
        // Fed via appendBuffer, the only multi-update-per-frame path.
        self.cloud_inst_buf = sg.makeBuffer(.{
            .usage = .{ .stream_update = true },
            .size = MAX_SKY_BAKES * @sizeOf(GpuInstance),
        });
    }

    fn build_pipeline(gpu_backend: sg.Backend, blend: bool) sg.Pipeline {
        return sg.makePipeline(.{
            .shader = sg.makeShader(shd.particleShaderDesc(gpu_backend)),
            // The no-blend variant only ever draws into the offscreen bake
            // pass: pin its color format to the bake image's RGBA8 and
            // declare no depth target, or Metal validation aborts when the
            // swapchain pipeline formats bleed into the offscreen pass.
            .depth = .{ .pixel_format = if (blend) .DEFAULT else .NONE },
            .layout = init: {
                var l = sg.VertexLayoutState{};
                l.attrs[shd.ATTR_particle_quad_corner] = .{ .format = .FLOAT2, .buffer_index = 0 };
                l.buffers[1].step_func = .PER_INSTANCE;
                l.buffers[1].step_rate = 1;
                l.attrs[shd.ATTR_particle_inst_pos] = .{ .format = .FLOAT2, .offset = 0, .buffer_index = 1 };
                l.attrs[shd.ATTR_particle_inst_stroke_size] = .{ .format = .FLOAT, .offset = 8, .buffer_index = 1 };
                l.attrs[shd.ATTR_particle_inst_fill_size] = .{ .format = .FLOAT, .offset = 12, .buffer_index = 1 };
                l.attrs[shd.ATTR_particle_inst_stroke_a] = .{ .format = .FLOAT, .offset = 16, .buffer_index = 1 };
                l.attrs[shd.ATTR_particle_inst_fill_a] = .{ .format = .FLOAT, .offset = 20, .buffer_index = 1 };
                l.attrs[shd.ATTR_particle_inst_shape] = .{ .format = .FLOAT, .offset = 24, .buffer_index = 1 };
                break :init l;
            },
            .index_type = .UINT16,
            .colors = init: {
                var c: [8]sg.ColorTargetState = @splat(.{});
                // Bake writes raw (non-premultiplied) rgb+alpha into an
                // empty texture; blit blends over the swapchain as usual.
                c[0] = .{
                    .pixel_format = if (blend) .DEFAULT else .RGBA8,
                    .blend = .{
                        .enabled = blend,
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
    }
};

fn to_f32x4(c: Rgba) [4]f32 {
    return .{
        @as(f32, @floatFromInt(c.r)) / 255.0,
        @as(f32, @floatFromInt(c.g)) / 255.0,
        @as(f32, @floatFromInt(c.b)) / 255.0,
        @as(f32, @floatFromInt(c.a)) / 255.0,
    };
}

fn ortho(left: f32, right: f32, bottom: f32, top: f32) [16]f32 {
    return .{
        2.0 / (right - left),             0.0,                              0.0,  0.0,
        0.0,                              2.0 / (top - bottom),             0.0,  0.0,
        0.0,                              0.0,                              -1.0, 0.0,
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), 0.0,  1.0,
    };
}
