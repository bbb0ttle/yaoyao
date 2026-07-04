const std = @import("std");
const app = @import("app.zig");

var canvas: app.Canvas = undefined;
var heart: app.HeartSystem = undefined;
var heart_ready: bool = false;
var resize_cooldown: u32 = 0;
var days_text_buf: [32]u8 = undefined;
var days_text_len: usize = 0;

export fn init() void {
    canvas = app.Canvas.init(std.heap.page_allocator);
}

export fn get_framebuffer_ptr() usize {
    if (canvas.buf.len == 0) return 0;
    return @intFromPtr(&canvas.buf[0]);
}

export fn get_width() u32 {
    return canvas.width;
}

export fn get_height() u32 {
    return canvas.height;
}

export fn resize(new_w: u32, new_h: u32) void {
    canvas.resize(new_w, new_h) catch return;
    heart_ready = false;
    resize_cooldown = 30;
}

export fn update_frame(elapsed: f32, unix_ms: f64, dpr: f32) void {
    if (canvas.buf.len == 0) return;

    if (resize_cooldown > 0) {
        resize_cooldown -= 1;
        const fb = canvas.frameBuffer();
        fb.clear(.{ .r = 251, .g = 192, .b = 93, .a = 255 });
        return;
    }

    if (!heart_ready) {
        const hx: f32 = @as(f32, @floatFromInt(canvas.width)) / 2.0 - 50.0 * dpr;
        const hy: f32 = @as(f32, @floatFromInt(canvas.height)) / 2.0 - 200.0 * dpr;
        heart = app.HeartSystem.init(elapsed, hx, hy, @as(f32, @floatFromInt(canvas.height)), dpr);
        heart_ready = true;
    }

    const start_ms: f64 = 1660694400000.0;
    const diff_days = (unix_ms - start_ms) / (1000.0 * 60.0 * 60.0 * 24.0);

    const int_part: u64 = @intFromFloat(@floor(diff_days));
    const frac: f64 = diff_days - @floor(diff_days);
    days_text_len = 0;
    formatUint(int_part);
    if (days_text_len < days_text_buf.len) {
        days_text_buf[days_text_len] = '.';
        days_text_len += 1;
    }
    var f = frac;
    var digits: usize = 0;
    while (digits < 10) : (digits += 1) {
        f *= 10.0;
        const d: u8 = @intFromFloat(@floor(f));
        f -= @floor(f);
        if (days_text_len < days_text_buf.len) {
            days_text_buf[days_text_len] = '0' + d;
            days_text_len += 1;
        }
    }

    // append " DAYS"
    const suffix = " DAYS";
    for (suffix) |ch| {
        if (days_text_len < days_text_buf.len) {
            days_text_buf[days_text_len] = ch;
            days_text_len += 1;
        }
    }

    const fb = canvas.frameBuffer();
    fb.clear(.{ .r = 251, .g = 192, .b = 93, .a = 255 });

    heart.update(elapsed);
    heart.render(fb, elapsed);

    const text_scale: u32 = @max(1, @as(u32, @intFromFloat(2.0 * dpr)));
    const text_y: i32 = @as(i32, @intCast(canvas.height)) - @as(i32, @intFromFloat(80.0 * dpr));
    const text_x: i32 = @divTrunc(@as(i32, @intCast(canvas.width)), 2) - @as(i32, @intFromFloat(50.0 * dpr)) + @as(i32, @intFromFloat(15.0 * dpr));
    fb.drawText(text_x, text_y, days_text_buf[0..days_text_len], text_scale, .{ .r = 251, .g = 93, .b = 99, .a = 230 });
}

fn formatUint(n: u64) void {
    if (n == 0) {
        if (days_text_len < days_text_buf.len) {
            days_text_buf[days_text_len] = '0';
            days_text_len += 1;
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
        if (days_text_len < days_text_buf.len) {
            days_text_buf[days_text_len] = tmp[j];
            days_text_len += 1;
        }
    }
}
