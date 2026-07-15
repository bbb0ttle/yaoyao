const sokol = @import("sokol");
const sg = sokol.gfx;
const shd = @import("../shaders/particle.glsl.zig");
const backend = @import("../platform/backend.zig");
const Rgba = @import("../core/types.zig").Rgba;

pub const MAX_INSTANCES: u32 = 10000;
pub const STROKE_WIDTH: f32 = 2.0;

pub const GpuInstance = extern struct {
    pos_x: f32,
    pos_y: f32,
    stroke_size: f32,
    fill_size: f32,
    stroke_a: f32,
    fill_a: f32,
    shape: f32,
};

pub const GpuState = struct {
    pass_action: sg.PassAction,
    pip: sg.Pipeline,
    bind: sg.Bindings,
    instance_buffer: []GpuInstance,
    instance_count: u32,
    allocator: std.mem.Allocator,

    const std = @import("std");

    pub fn init(allocator: std.mem.Allocator) !GpuState {
        const instance_buffer = try allocator.alloc(GpuInstance, MAX_INSTANCES);

        sg.setup(.{
            .environment = @import("sokol").glue.environment(),
            .logger = .{ .func = @import("sokol").log.func },
        });

        var self = GpuState{
            .pass_action = .{},
            .pip = .{},
            .bind = .{},
            .instance_buffer = instance_buffer,
            .instance_count = 0,
            .allocator = allocator,
        };

        self.pass_action.colors[0] = .{
            .load_action = .CLEAR,
            .clear_value = .{ .r = 169.0 / 255.0, .g = 229.0 / 255.0, .b = 214.0 / 255.0, .a = 1.0 },
        };

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

        const gpu_backend = backend.detect_gpu_backend();
        self.pip = sg.makePipeline(.{
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

        return self;
    }

    pub fn deinit(self: *GpuState) void {
        self.allocator.free(self.instance_buffer);
        sg.shutdown();
    }

    pub fn write_instance(self: *GpuState, idx: u32, inst: GpuInstance) void {
        if (idx < MAX_INSTANCES) {
            self.instance_buffer[idx] = inst;
        }
    }

    pub fn upload_instances(self: *GpuState) void {
        sg.updateBuffer(self.bind.vertex_buffers[1], sg.asRange(self.instance_buffer[0..self.instance_count]));
    }

    pub fn render(self: *GpuState, w: f32, h: f32) void {
        const mvp = _ortho(0, w, h, 0);
        const vs_params = shd.VsParams{ .mvp = mvp };
        const fs_params = shd.FsParams{
            .fill_color = [_]f32{
                @as(f32, @floatFromInt(Rgba.heart_fill.r)) / 255.0,
                @as(f32, @floatFromInt(Rgba.heart_fill.g)) / 255.0,
                @as(f32, @floatFromInt(Rgba.heart_fill.b)) / 255.0,
                @as(f32, @floatFromInt(Rgba.heart_fill.a)) / 255.0,
            },
            .stroke_color = [_]f32{
                @as(f32, @floatFromInt(Rgba.heart_stroke.r)) / 255.0,
                @as(f32, @floatFromInt(Rgba.heart_stroke.g)) / 255.0,
                @as(f32, @floatFromInt(Rgba.heart_stroke.b)) / 255.0,
                @as(f32, @floatFromInt(Rgba.heart_stroke.a)) / 255.0,
            },
        };

        const sglue = @import("sokol").glue;
        sg.beginPass(.{ .action = self.pass_action, .swapchain = sglue.swapchain() });
        if (self.instance_count > 0) {
            sg.applyPipeline(self.pip);
            sg.applyBindings(self.bind);
            sg.applyUniforms(shd.UB_vs_params, sg.asRange(&vs_params));
            sg.applyUniforms(shd.UB_fs_params, sg.asRange(&fs_params));
            sg.draw(0, 6, @intCast(self.instance_count));
        }
        sg.endPass();
        sg.commit();
    }
};

fn _ortho(left: f32, right: f32, bottom: f32, top: f32) [16]f32 {
    return .{
        2.0 / (right - left),             0.0,                              0.0,  0.0,
        0.0,                              2.0 / (top - bottom),             0.0,  0.0,
        0.0,                              0.0,                              -1.0, 0.0,
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), 0.0,  1.0,
    };
}
