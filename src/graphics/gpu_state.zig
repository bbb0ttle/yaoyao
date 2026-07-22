//! GPU state management: pipeline, buffers, instanced rendering.

const std = @import("std");

const sokol = @import("sokol");
const sg = sokol.gfx;
const shd = @import("../shaders/particle.glsl.zig");
const backend = @import("../platform/backend.zig");
const Rgba = @import("../core/types.zig").Rgba;
const Theme = @import("../core/theme.zig").Theme;

pub const MAX_INSTANCES: u32 = 10000;
pub const STROKE_WIDTH: f32 = 2.0;

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
        self.pip = build_pipeline();

        return self;
    }

    pub fn deinit(self: *Self) void {
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
        sg.beginPass(.{ .action = self.pass_action, .swapchain = sglue.swapchain() });
        if (self.instance_count > 0) {
            sg.applyPipeline(self.pip);
            sg.applyBindings(self.bind);
            sg.applyUniforms(shd.UB_vs_params, sg.asRange(&self.vs_params));
            sg.applyUniforms(shd.UB_fs_params, sg.asRange(&self.fs_params));
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
    }

    fn build_pipeline() sg.Pipeline {
        const gpu_backend = backend.detect_gpu_backend();
        return sg.makePipeline(.{
            .shader = sg.makeShader(shd.particleShaderDesc(gpu_backend)),
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
