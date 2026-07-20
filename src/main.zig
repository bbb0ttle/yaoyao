//! Application entry point and sokol C ABI callbacks.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.oayao);

const sokol = @import("sokol");
const sapp = sokol.app;
const slog = sokol.log;

const App = @import("app.zig").App;
const CounterHeartsFrame = @import("app.zig").CounterHeartsFrame;
const bootstrap = @import("platform/bootstrap.zig");

// Named allocator constant — replace with debugging allocator as needed.
const APP_ALLOCATOR = std.heap.c_allocator;

// Global app pointer — the minimum necessary global for sokol's C ABI
// callbacks which provide no userdata parameter.
var g_app: ?*App = null;

export fn init() void {
    const app = App.init(APP_ALLOCATOR) catch @panic("OOM");
    g_app = app;
    bootstrap.bootstrap();
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
    gpu.render(w, h, app.current_theme());
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

export fn trigger_meteor_shower(x: f32, y: f32) void {
    if (g_app) |app| {
        app.handle_click(x, y);
    }
}

export fn oayao_spawn_heart(event_id: [*:0]const u8) void {
    if (g_app) |app| {
        const len = std.mem.sliceTo(event_id, 0).len;
        const elapsed: f32 = @floatCast(sapp.frameDuration());
        app.spawn_heart(event_id[0..len], elapsed) catch |err| {
            log.warn("spawn_heart failed: {}", .{err});
        };
    }
}

export fn oayao_remove_heart(event_id: [*:0]const u8) void {
    if (g_app) |app| {
        const len = std.mem.sliceTo(event_id, 0).len;
        app.remove_heart(event_id[0..len]);
    }
}

export fn oayao_counter_hearts_frame() CounterHeartsFrame {
    if (g_app) |app| {
        return app.counter_hearts_frame();
    }
    return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
}

export fn oayao_sync_hearts(active_ids: [*:0]const u8) void {
    if (g_app) |app| {
        const slice: [:0]const u8 = std.mem.span(active_ids);
        app.sync_hearts(slice);
    }
}

export fn oayao_set_heart_tap_callback(cb: ?*const fn ([*:0]const u8) callconv(.c) void) void {
    if (g_app) |app| {
        app.set_heart_tap_callback(cb);
    }
}

export fn oayao_set_counter_tap_callback(cb: ?*const fn () callconv(.c) void) void {
    if (g_app) |app| {
        app.set_counter_tap_callback(cb);
    }
}

export fn oayao_set_days_counter_start_ms(ms: f64) void {
    if (g_app) |app| {
        app.set_days_counter_start_ms(ms);
    }
}

export fn oayao_days_counter_default_start_ms() f64 {
    return @import("app.zig").DAYS_COUNTER_DEFAULT_START_MS;
}

export fn oayao_transition_to_theme(theme_id: u32) void {
    if (g_app) |app| {
        app.transition_to_theme(theme_id);
    }
}

export fn oayao_set_custom_theme_color(role: u32, r: u8, g: u8, b: u8) void {
    if (g_app) |app| {
        app.set_custom_theme_color(role, r, g, b);
    }
}

export fn oayao_set_heart_opacity(opacity: f32) void {
    if (g_app) |app| {
        app.set_heart_opacity(opacity);
    }
}

export fn oayao_set_heart_size_scale(size_scale: f32) void {
    if (g_app) |app| {
        app.set_heart_size_scale(size_scale);
    }
}

export fn oayao_set_heart_motion(mode: u32) void {
    if (g_app) |app| {
        app.set_heart_motion(mode);
    }
}

export fn oayao_set_heart_y(fraction: f32) void {
    if (g_app) |app| {
        app.set_heart_y_fraction(fraction);
    }
}

export fn oayao_reset_heart_y() void {
    if (g_app) |app| {
        app.reset_heart_y();
    }
}

export fn oayao_reset_heart_config() void {
    if (g_app) |app| {
        app.reset_heart_config();
    }
}

export fn oayao_set_nebula_enabled(enabled: u32) void {
    if (g_app) |app| {
        app.set_nebula_enabled(enabled != 0);
    }
}

export fn oayao_default_heart_y() f32 {
    const app = g_app orelse return 0.5;
    return app.default_heart_y();
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 800,
        .height = 600,
        .window_title = "oayao",
        .logger = .{ .func = slog.func },
        .high_dpi = true,
    });
}
