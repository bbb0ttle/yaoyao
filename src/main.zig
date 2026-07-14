const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const slog = sokol.log;

const App = @import("app.zig").App;

// Global app pointer — the minimum necessary global for sokol's C ABI
// callbacks which provide no userdata parameter.
var g_app: ?*App = null;

export fn init() void {
    const app = App.init(std.heap.page_allocator) catch @panic("OOM");
    g_app = app;
}

export fn frame() void {
    const app = g_app orelse return;
    const elapsed = app.tick_elapsed();

    const w: f32 = sapp.widthf();
    const h: f32 = sapp.heightf();
    const dpr = sapp.dpiScale();

    app.cooldown_tick();
    if (app.needs_system_init()) {
        app.init_systems(w, h, elapsed);
    }

    if (app.can_render()) {
        app.update_and_fill_buffers(w, h, elapsed, dpr);
    }

    const gpu = app.gpu_mut();
    gpu.upload_instances();
    gpu.render(w, h);
}

export fn cleanup() void {
    if (g_app) |app| {
        app.deinit();
        g_app = null;
    }
}

export fn event(ev: [*c]const sapp.Event) void {
    const app = g_app orelse return;
    switch (ev.*.type) {
        .TOUCHES_BEGAN => {
            const t = ev.*.touches[0];
            app.handle_click(t.pos_x, t.pos_y);
        },
        .MOUSE_DOWN => {
            app.handle_click(ev.*.mouse_x, ev.*.mouse_y);
        },
        .RESIZED => {
            app.handle_resize();
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
