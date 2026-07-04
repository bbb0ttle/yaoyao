const std = @import("std");
const app = @import("app.zig");

var canvas: app.Canvas = undefined;
var heart: app.HeartSystem = undefined;
var heart_ready: bool = false;
var resize_cooldown: u32 = 0;
var transition_start: f32 = 0.0;
var days_text_buf: [32]u8 = undefined;
var days_text_len: usize = 0;

const TRANSITION_DURATION: f32 = 3.0;

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

    // compute days text first so we know its width for centering
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

    // center the text + float-heart group on screen
    const text_scale: u32 = @max(1, @as(u32, @intFromFloat(2.0 * dpr)));
    const char_stride: i32 = @as(i32, @intCast(4 * text_scale)); // 3px glyph + 1px spacing
    const text_width_px: i32 = @as(i32, @intCast(days_text_len)) * char_stride;
    const float_spread: i32 = @as(i32, @intFromFloat(7.0 * dpr));
    const gap: i32 = @as(i32, @intFromFloat(15.0 * dpr));
    const group_width: i32 = float_spread + gap + text_width_px;
    const group_left: i32 = @divTrunc(@as(i32, @intCast(canvas.width)), 2) - @divTrunc(group_width, 2);
    const text_x: i32 = group_left + float_spread + gap;
    const text_y: i32 = @as(i32, @intCast(canvas.height)) - @as(i32, @intFromFloat(80.0 * dpr));
    const fp_y: f32 = @as(f32, @floatFromInt(canvas.height)) - 80.0 * dpr;

    if (resize_cooldown > 0) {
        resize_cooldown -= 1;
        const fb = canvas.frameBuffer();
        fb.clear(.{ .r = 251, .g = 192, .b = 93, .a = 255 });
        return;
    }

    if (!heart_ready) {
        const hx: f32 = @as(f32, @floatFromInt(canvas.width)) / 2.0 - 50.0 * dpr;
        const hy: f32 = @as(f32, @floatFromInt(canvas.height)) / 2.0 - 200.0 * dpr;
        heart = app.HeartSystem.init(elapsed, hx, hy, @as(f32, @floatFromInt(canvas.height)), @as(f32, @floatFromInt(group_left)), fp_y, dpr);
        heart_ready = true;
        transition_start = elapsed;
    }

    const t: f32 = @min(1.0, (elapsed - transition_start) / TRANSITION_DURATION);

    const fb = canvas.frameBuffer();
    fb.clear(.{ .r = 251, .g = 192, .b = 93, .a = 255 });

    heart.update(elapsed);
    heart.render(fb, elapsed, t);

    const text_g: u8 = @intFromFloat(192.0 - 99.0 * t);
    const text_b: u8 = @intFromFloat(93.0 + 6.0 * t);
    const text_a: u8 = @intFromFloat(255.0 - 25.0 * t);
    fb.drawText(text_x, text_y, days_text_buf[0..days_text_len], text_scale, .{ .r = 251, .g = text_g, .b = text_b, .a = text_a });
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
