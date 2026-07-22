//! Heart curve parametric equations and breathing animation math.

const std = @import("std");

const Vec2 = @import("types.zig").Vec2;

/// Parametric heart curve: returns a Vec2 on the heart contour at parameter t.
pub fn create_heart_pos(t: f32) Vec2 {
    const s = @sin(t);
    const x = 2.0 * s * s * s;
    const y = -(2.0 * ((13.0 * @cos(t) - 5.0 * @cos(2.0 * t) - 2.0 * @cos(3.0 * t) - @cos(4.0 * t)) / 16.0));
    return Vec2{ .x = x, .y = y };
}

/// exp(sin) oscillation between min and max over one period: the exponential
/// mapping dwells gently at the extremes, reading as a calm held breath.
pub fn breath_cycle(sec: f32, period_sec: f32, min: f32, max: f32) f32 {
    const phase = sec * 2.0 * std.math.pi / period_sec;
    const e = std.math.e;
    const a = 1.0 / e;
    const s = (max - min) / (e - a);
    return @mulAdd(f32, @exp(@sin(phase)), s, min - a * s);
}

/// Heartbeat pulse: the exp(sin) curve at a fast ~90bpm rate.
pub fn breath(sec: f32, min: f32, max: f32) f32 {
    return breath_cycle(sec, 2.0 / 3.0, min, max);
}

pub fn scale(val: f32, a: f32, b: f32) f32 {
    return val * b / a;
}

pub const SpringState = struct { x: f32, y: f32, vx: f32, vy: f32 };

/// Ease-out power-curve speed profile with a cruise floor: velocity along
/// p(u) = 1 - (1-u)^power, expressed against the remaining distance, but
/// never dropping below v0·floor_frac. Starts at v0, brakes only late and
/// only down to the floor — a meteor that barely slows before it lands.
/// Frame-rate independent, no timekeeping needed.
pub fn ease_out_speed(v0: f32, remaining: f32, total: f32, power: f32, floor_frac: f32) f32 {
    const r = @max(remaining, 0.0) / total;
    return v0 * (floor_frac + (1.0 - floor_frac) * std.math.pow(f32, r, (power - 1.0) / power));
}

/// One semi-implicit Euler step of a damped harmonic oscillator toward
/// (tx, ty). omega is angular frequency in rad/frame; zeta < 1 underdamps
/// the spring, giving the overshoot-and-settle of follow-through motion.
pub fn spring_step(x: f32, y: f32, vx: f32, vy: f32, tx: f32, ty: f32, omega: f32, zeta: f32) SpringState {
    const ax = -omega * omega * (x - tx) - 2.0 * zeta * omega * vx;
    const ay = -omega * omega * (y - ty) - 2.0 * zeta * omega * vy;
    const nvx = vx + ax;
    const nvy = vy + ay;
    return .{ .x = x + nvx, .y = y + nvy, .vx = nvx, .vy = nvy };
}
