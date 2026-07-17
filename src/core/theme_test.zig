const std = @import("std");
const testing = std.testing;
const theme_mod = @import("theme.zig");
const Theme = theme_mod.Theme;
const ThemeTransition = theme_mod.ThemeTransition;
const Rgba = @import("types.zig").Rgba;

test "theme_for resolves builtin and custom palettes" {
    const custom = Theme{
        .background = Rgba.BLACK,
        .heart_fill = Rgba.WHITE,
        .heart_stroke = Rgba.WHITE,
        .timer_text = Rgba.WHITE,
    };
    try testing.expectEqual(theme_mod.MINT, theme_mod.theme_for(.mint, custom));
    try testing.expectEqual(theme_mod.PEACH, theme_mod.theme_for(.peach, custom));
    try testing.expectEqual(custom, theme_mod.theme_for(.custom, custom));
}

test "set_color updates the addressed role only" {
    var theme = theme_mod.MINT;
    theme_mod.set_color(&theme, .background, Rgba.BLACK);
    try testing.expectEqual(Rgba.BLACK, theme.background);
    try testing.expectEqual(theme_mod.MINT.heart_fill, theme.heart_fill);
    try testing.expectEqual(theme_mod.MINT.heart_stroke, theme.heart_stroke);
    try testing.expectEqual(theme_mod.MINT.timer_text, theme.timer_text);
}

test "transition: current equals target after duration" {
    var tr = ThemeTransition.init(theme_mod.MINT);
    tr.transition_to(theme_mod.PEACH, 1.0);
    const done = tr.current(2.0);
    try testing.expectEqual(theme_mod.PEACH, done);
}

test "transition: midpoint blends channels" {
    const from = theme_mod.MINT;
    const to = theme_mod.PEACH;
    var tr = ThemeTransition.init(from);
    tr.transition_to(to, 0.0);
    const mid = tr.current(0.45);
    const lo = @min(from.background.r, to.background.r);
    const hi = @max(from.background.r, to.background.r);
    try testing.expect(mid.background.r >= lo and mid.background.r <= hi);
    try testing.expect(mid.background.r != from.background.r);
    try testing.expect(mid.background.r != to.background.r);
}

test "transition: clamps before start and retargets without popping" {
    var tr = ThemeTransition.init(theme_mod.MINT);
    tr.transition_to(theme_mod.PEACH, 1.0);
    try testing.expectEqual(theme_mod.MINT, tr.current(0.5));

    const halfway = tr.current(1.45);
    tr.transition_to(theme_mod.PEACH, 1.45);
    try testing.expectEqual(halfway, tr.current(1.45));
}
