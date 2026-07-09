const std = @import("std");
const app = @import("app.zig");
const particle = @import("Particle.zig");
const FrameBuffer = @import("FrameBuffer.zig").FrameBuffer;

var canvas: app.Canvas = undefined;
var heart: app.HeartSystem = undefined;
var heart_ready: bool = false;
var meteor: app.MeteorSystem = undefined;
var meteor_ready: bool = false;
var resize_cooldown: u32 = 0;
var transition_start: f32 = 0.0;
var days_text_buf: [32]u8 = undefined;
var days_text_len: usize = 0;

const TRANSITION_DURATION: f32 = 3.0;

var fb_ptr: [*]u8 = undefined;
var fb_ptr_set: bool = false;
var fb_width: u32 = 0;
var fb_height: u32 = 0;
var fb_bytes_per_row: u32 = 0;

fn currentFB() FrameBuffer {
    if (fb_ptr_set) {
        return FrameBuffer{
            .buf = fb_ptr[0 .. @as(usize, fb_height) * @as(usize, fb_bytes_per_row)],
            .width = fb_width,
            .height = fb_height,
            .bytes_per_row = fb_bytes_per_row,
        };
    }
    return canvas.frameBuffer();
}

fn currentWidth() u32 {
    return if (fb_ptr_set) fb_width else canvas.width;
}

fn currentHeight() u32 {
    return if (fb_ptr_set) fb_height else canvas.height;
}

export fn init() void {
    canvas = app.Canvas.init(std.heap.page_allocator);
}

export fn init_with_buffer(buf: [*]u8, w: u32, h: u32, bpr: u32) void {
    fb_ptr = buf;
    fb_ptr_set = true;
    fb_width = w;
    fb_height = h;
    fb_bytes_per_row = bpr;
    heart_ready = false;
    meteor_ready = false;
    resize_cooldown = 30;
}

export fn get_framebuffer_ptr() usize {
    if (fb_ptr_set) return @intFromPtr(fb_ptr);
    if (canvas.buf.len == 0) return 0;
    return @intFromPtr(&canvas.buf[0]);
}

export fn get_width() u32 {
    return currentWidth();
}

export fn get_height() u32 {
    return currentHeight();
}

export fn resize(new_w: u32, new_h: u32) void {
    canvas.resize(new_w, new_h) catch return;
    heart_ready = false;
    meteor_ready = false;
    resize_cooldown = 30;
}

export fn set_buffer(buf: [*]u8) void {
    fb_ptr = buf;
}

export fn resize_with_buffer(buf: [*]u8, w: u32, h: u32, bpr: u32) void {
    fb_ptr = buf;
    fb_ptr_set = true;
    fb_width = w;
    fb_height = h;
    fb_bytes_per_row = bpr;
    heart_ready = false;
    meteor_ready = false;
    resize_cooldown = 30;
}

export fn update_frame(elapsed: f32, unix_ms: f64, dpr: f32) void {
    const fb = currentFB();
    if (fb.buf.len == 0) return;
    const cw = fb.width;
    const ch = fb.height;

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
    for (suffix) |byte| {
        if (days_text_len < days_text_buf.len) {
            days_text_buf[days_text_len] = byte;
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
    const group_left: i32 = @divTrunc(@as(i32, @intCast(cw)), 2) - @divTrunc(group_width, 2);
    const text_x: i32 = group_left + float_spread + gap;
    const text_y: i32 = @as(i32, @intCast(ch)) - @as(i32, @intFromFloat(80.0 * dpr));
    const fp_y: f32 = @as(f32, @floatFromInt(ch)) - 80.0 * dpr;

    if (resize_cooldown > 0) {
        resize_cooldown -= 1;
        fb.clear(app.business.Rgba.heart_bg);
        return;
    }

    if (!heart_ready) {
        const hx: f32 = @as(f32, @floatFromInt(cw)) / 2.0 - 50.0 * dpr;
        const hy: f32 = @as(f32, @floatFromInt(ch)) / 2.0 - 200.0 * dpr;
        heart = app.HeartSystem.init(elapsed, hx, hy, @as(f32, @floatFromInt(ch)), @as(f32, @floatFromInt(group_left)), fp_y, dpr);
        heart_ready = true;
        transition_start = elapsed;

        if (!meteor_ready) {
            meteor = app.MeteorSystem.init(@floatFromInt(cw), @floatFromInt(ch), dpr);
            meteor_ready = true;
        }
    }

    const t: f32 = @min(1.0, (elapsed - transition_start) / TRANSITION_DURATION);

    fb.clear(app.business.Rgba.heart_bg);

    heart.update(elapsed);
    particle.collectAlive();
    heart.render(fb, elapsed, t);

    if (meteor_ready) {
        meteor.update();
    }

    fb.drawText(text_x, text_y, days_text_buf[0..days_text_len], text_scale, app.business.Rgba.white);
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

export fn show_meteor_shower(click_x: f32, click_y: f32) void {
    if (!meteor_ready) return;
    meteor.falling(click_x, click_y);
}

// iOS C ABI aliases (kept alongside WASM exports above)
export fn oy_init() void { init(); }
export fn oy_init_with_buffer(buf: [*]u8, w: u32, h: u32, bpr: u32) void { init_with_buffer(buf, w, h, bpr); }
export fn oy_get_framebuffer_ptr() usize { return get_framebuffer_ptr(); }
export fn oy_get_width() u32 { return get_width(); }
export fn oy_get_height() u32 { return get_height(); }
export fn oy_resize(new_w: u32, new_h: u32) void { resize(new_w, new_h); }
export fn oy_resize_with_buffer(buf: [*]u8, w: u32, h: u32, bpr: u32) void { resize_with_buffer(buf, w, h, bpr); }
export fn oy_set_buffer(buf: [*]u8) void { set_buffer(buf); }
export fn oy_update_frame(elapsed: f32, unix_ms: f64, dpr: f32) void { update_frame(elapsed, unix_ms, dpr); }
export fn oy_show_meteor_shower(click_x: f32, click_y: f32) void { show_meteor_shower(click_x, click_y); }
