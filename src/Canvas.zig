const std = @import("std");
const FrameBuffer = @import("FrameBuffer.zig").FrameBuffer;

pub const Canvas = struct {
    buf: []u8,
    width: u32,
    height: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Canvas {
        return Canvas{
            .buf = &[_]u8{},
            .width = 800,
            .height = 600,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Canvas) void {
        if (self.buf.len != 0) {
            self.allocator.free(self.buf);
            self.buf = &[_]u8{};
        }
    }

    pub fn resize(self: *Canvas, new_w: u32, new_h: u32) !void {
        const fb = FrameBuffer{ .buf = self.buf, .width = self.width, .height = self.height, .bytes_per_row = self.width * 4 };
        const new_fb = try fb.resize(new_w, new_h, self.allocator);
        if (self.buf.len != 0) self.allocator.free(self.buf);
        self.buf = new_fb.buf;
        self.width = new_fb.width;
        self.height = new_fb.height;
    }

    pub fn frameBuffer(self: *const Canvas) FrameBuffer {
        return FrameBuffer{ .buf = self.buf, .width = self.width, .height = self.height, .bytes_per_row = self.width * 4 };
    }
};
