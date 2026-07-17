//! Theme definitions and animated theme transitions.

const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.theme);

const Rgba = @import("types.zig").Rgba;

const TRANSITION_DURATION_SEC: f32 = 0.9;

/// Key colors shared by every rendered element.
pub const Theme = struct {
    const Self = @This();

    background: Rgba,
    heart_fill: Rgba,
    heart_stroke: Rgba,
    timer_text: Rgba,
};

/// Identifiers for the themes; values are part of the C ABI.
/// `.custom` resolves to a runtime-provided palette set by the host layer.
pub const ThemeId = enum(u32) {
    mint = 0,
    peach = 1,
    custom = 2,
};

/// Roles of the key colors shared by every rendered element.
pub const ColorRole = enum(u32) {
    background = 0,
    heart_fill = 1,
    heart_stroke = 2,
    timer_text = 3,
};

pub const MINT: Theme = .{
    .background = .{ .r = 169, .g = 229, .b = 214, .a = 255 },
    .heart_fill = Rgba.WHITE,
    .heart_stroke = .{ .r = 219, .g = 236, .b = 230, .a = 255 },
    .timer_text = Rgba.WHITE,
};

pub const PEACH: Theme = .{
    .background = .{ .r = 245, .g = 205, .b = 215, .a = 255 },
    .heart_fill = Rgba.WHITE,
    .heart_stroke = .{ .r = 251, .g = 230, .b = 236, .a = 255 },
    .timer_text = Rgba.WHITE,
};

pub fn theme_for(id: ThemeId, custom: Theme) Theme {
    return switch (id) {
        .mint => MINT,
        .peach => PEACH,
        .custom => custom,
    };
}

pub fn set_color(theme: *Theme, role: ColorRole, color: Rgba) void {
    switch (role) {
        .background => theme.background = color,
        .heart_fill => theme.heart_fill = color,
        .heart_stroke => theme.heart_stroke = color,
        .timer_text => theme.timer_text = color,
    }
}

/// Blends between two themes over TRANSITION_DURATION_SEC with smoothstep easing.
pub const ThemeTransition = struct {
    const Self = @This();

    from: Theme,
    to: Theme,
    start_sec: f32,

    pub fn init(theme: Theme) Self {
        return .{ .from = theme, .to = theme, .start_sec = 0.0 };
    }

    /// Begin transitioning to `theme`; the current interpolated color becomes
    /// the new starting point so retargeting mid-transition never pops.
    pub fn transition_to(self: *Self, theme: Theme, elapsed: f32) void {
        self.from = self.current(elapsed);
        self.to = theme;
        self.start_sec = elapsed;
    }

    pub fn current(self: *const Self, elapsed: f32) Theme {
        const raw = (elapsed - self.start_sec) / TRANSITION_DURATION_SEC;
        const t = std.math.clamp(raw, 0.0, 1.0);
        const eased = t * t * (3.0 - 2.0 * t);
        return .{
            .background = lerp_rgba(self.from.background, self.to.background, eased),
            .heart_fill = lerp_rgba(self.from.heart_fill, self.to.heart_fill, eased),
            .heart_stroke = lerp_rgba(self.from.heart_stroke, self.to.heart_stroke, eased),
            .timer_text = lerp_rgba(self.from.timer_text, self.to.timer_text, eased),
        };
    }
};

fn lerp_channel(a: u8, b: u8, t: f32) u8 {
    const af: f32 = @floatFromInt(a);
    const bf: f32 = @floatFromInt(b);
    return @intFromFloat(@round(af + (bf - af) * t));
}

fn lerp_rgba(a: Rgba, b: Rgba, t: f32) Rgba {
    return .{
        .r = lerp_channel(a.r, b.r, t),
        .g = lerp_channel(a.g, b.g, t),
        .b = lerp_channel(a.b, b.b, t),
        .a = lerp_channel(a.a, b.a, t),
    };
}
