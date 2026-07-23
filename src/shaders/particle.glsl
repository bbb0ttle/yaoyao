// Particle instancing shader — heart/diamond SDF point sprites.
// Single-instance stroke+fill: stroke and fill are composited in the fragment
// shader from one GpuInstance, avoiding the double-instance overdraw.

@vs vs_particle
layout(binding=0) uniform vs_params {
    mat4 mvp;
};

// Static quad corners: (0,0), (1,0), (0,1), (1,1)
in vec2 quad_corner;

// Per-instance data (see GpuInstance in gpu_state.zig):
// offset  0: vec2  inst_pos          — particle center in world pixels
// offset  8: float inst_stroke_size   — outer radius (display_size + stroke_width)
// offset 12: float inst_fill_size     — inner fill radius (display_size)
// offset 16: float inst_stroke_a      — stroke alpha
// offset 20: float inst_fill_a        — fill alpha
// offset 24: float inst_shape         — 0=diamond, 1=heart, 2=square
in vec2 inst_pos;
in float inst_stroke_size;
in float inst_fill_size;
in float inst_stroke_a;
in float inst_fill_a;
in float inst_shape;

out vec2 v_uv;
out vec2 v_pos;
out float v_stroke_size;
out float v_fill_size;
out float v_stroke_a;
out float v_fill_a;
out float v_shape;

void main() {
    vec2 local = (quad_corner - 0.5) * 2.0;
    // Quad covers the larger stroke extent so it encloses both stroke and fill
    vec2 world = local * inst_stroke_size + inst_pos;
    gl_Position = mvp * vec4(world, 0.0, 1.0);
    v_uv = local;  // [-1, 1] in stroke-size world space
    v_pos = inst_pos;
    v_stroke_size = inst_stroke_size;
    v_fill_size = inst_fill_size;
    v_stroke_a = inst_stroke_a;
    v_fill_a = inst_fill_a;
    v_shape = inst_shape;
}
@end

@fs fs_particle
layout(binding=1) uniform fs_params {
    vec4 fill_color;
    vec4 stroke_color;
    vec4 text_color;
};

in vec2 v_uv;
in vec2 v_pos;
in float v_stroke_size;
in float v_fill_size;
in float v_stroke_a;
in float v_fill_a;
in float v_shape;
out vec4 frag_color;

// Hash & value noise for the nebula's irregular shapes.
// Sine-free hash (Hoskins) — much cheaper ALU than fract(sin(...)).
float hash2(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1030);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
               mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        v += a * vnoise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

float eval_sdf(vec2 uv, float shape) {
    if (shape < 0.5) {
        // Diamond SDF: |x| + |y| <= 1
        return 1.0 - (abs(uv.x) + abs(uv.y));
    } else if (shape < 1.5) {
        // Heart: exact distance field (two arcs + straight tip edge), so the
        // AA band is uniform and the stroke ring never breaks. uv is y-down
        // in [-1,1]; heart coords are y-up with the tip at the origin.
        vec2 p = vec2(uv.x, 0.87 - uv.y) / 1.2;
        p.x = abs(p.x);
        float d;
        if (p.y + p.x > 1.0) {
            d = length(p - vec2(0.25, 0.75)) - 0.353553;
        } else {
            vec2 m = vec2(0.5 * max(p.x + p.y, 0.0));
            d = sqrt(min(dot(p - vec2(0.0, 1.0), p - vec2(0.0, 1.0)),
                         dot(p - m, p - m))) * sign(p.x - p.y);
        }
        return -d * 1.2;  // positive inside, in uv units
    } else {
        // Filled square for text pixels — fully opaque
        return 2.0;
    }
}

void main() {
    // Lenticular lens (shape 6): a flat, polished lens with stacked
    // internal tonal bands — the smooth, elongated saucer shape of
    // standing-wave clouds. No FBM on the envelope: lenticulars are
    // defined by their glassy smoothness. v_stroke_a carries the
    // per-lens seed.
    if (v_shape > 5.5) {
        vec2 uv = v_uv;
        // Lens reaches zero at |x|=1 and |y|≈1/3 — ~3:1 width-to-height,
        // fully contained within the quad so edges fade naturally.
        float lens = 1.0 - (uv.x * uv.x * 1.0 + uv.y * uv.y * 9.0);
        float lens_c = clamp(lens, 0.0, 1.0);
        // Bend band samples along the lens arc (yy offsets up to ~4× the
        // half-height) so the stacked-plate stripes follow the saucer curve
        // instead of running flat.
        float yy = uv.y + 1.4 * uv.x * uv.x;
        float band1 = sin(yy * 18.0 + v_stroke_a * 0.08) * 0.5 + 0.5;
        float band2 = sin(yy * 7.0 + v_stroke_a * 0.15 + 1.2) * 0.5 + 0.5;
        // Low-frequency layer deepens the plate pile.
        float band3 = sin(yy * 2.5 + v_stroke_a * 0.05) * 0.5 + 0.5;
        float bands = band1 * 0.5 + band2 * 0.3 + band3 * 0.25;
        bands = mix(1.0, bands, smoothstep(0.0, 0.5, lens) * 0.4);
        // Sharp outer rim + concave interior highlight; sun-above lighting —
        // bright crown, shaded base (uv.y is down).
        float body = smoothstep(0.0, 0.22, lens) * pow(lens_c, 0.5) * (0.5 + 0.3 * bands);
        body *= mix(1.18, 0.62, smoothstep(-0.33, 0.33, uv.y));
        // Crown rim light pinched to a narrow band along the upper curve
        float crown = smoothstep(0.0, 0.22, lens) * smoothstep(0.30, 0.06, lens);
        crown *= (1.0 - abs(uv.x) * 1.05) * 0.35;
        float a = body + crown;
        // Faint iridescence confined to the thin edge band
        float rim = smoothstep(0.02, 0.12, lens) * smoothstep(0.30, 0.10, lens);
        vec3 irid = 1.0 + 0.08 * rim * sin(yy * 24.0 + v_stroke_a * 0.1 + vec3(0.0, 2.09, 4.19));
        frag_color = vec4(fill_color.rgb * irid, a * v_fill_a);
        return;
    }

    // Cirrus streak (shape 5): wind-sheared ice filaments — ridged fbm
    // sampled with a y-shear so the wisps hook, inside a long horizontal
    // envelope. Thin and translucent.
    if (v_shape > 4.5) {
        vec2 uv = v_uv;
        float e = 1.0 - (uv.x * uv.x + (4.0 * uv.y) * (4.0 * uv.y));
        vec2 sp = vec2(uv.x * 1.5, uv.y * 8.0) + vec2(uv.y * 2.0, 0.0) + v_stroke_a;
        float wisp = 1.0 - abs(2.0 * fbm(sp) - 1.0);
        float a = smoothstep(0.55, 0.9, wisp) * clamp(e, 0.0, 1.0) * 0.5;
        frag_color = vec4(fill_color.rgb, a * v_fill_a);
        return;
    }

    // Cumulus puff (shape 4): a dome-enveloped fbm blob — bright billowing
    // crests, shaded flat base, like a summer afternoon cloud. v_stroke_a
    // carries the puff's fbm seed so the pattern stays rigid while the
    // puff drifts across the sky.
    if (v_shape > 3.5) {
        vec2 uv = v_uv;
        float dome = 1.0 - dot(uv * vec2(1.0, 1.25), uv * vec2(1.0, 1.25));
        dome -= smoothstep(0.15, 0.75, uv.y) * 0.5; // flatten and fade the base
        float n = fbm(uv * 2.8 + v_stroke_a) * 0.85 + dome * 0.9 - 0.28;
        // Monochrome puff: depth comes from alpha alone — dense crests read
        // solid, the thin base and rims fade away.
        float body = smoothstep(0.22, 0.5, n);
        float crest = clamp(dome * 0.85 - uv.y * 1.05 + (n - 0.45) * 1.2, 0.0, 1.0);
        frag_color = vec4(fill_color.rgb, body * (0.55 + 0.45 * crest) * v_fill_a);
        return;
    }

    // Stroke SDF at stroke scale (v_uv is already in stroke-local space)
    float d_stroke = eval_sdf(v_uv, v_shape);
    float stroke_aa = 1.0 / max(v_stroke_size, 0.5);
    float sa = smoothstep(-stroke_aa, stroke_aa, d_stroke) * v_stroke_a;

    // Fill SDF at fill scale — scale v_uv so fill boundary aligns with unit circle
    float fill_ratio = v_fill_size / max(v_stroke_size, 0.5);
    vec2 fill_uv = v_uv / fill_ratio;
    float d_fill = eval_sdf(fill_uv, v_shape);
    float fill_aa = 1.0 / max(v_fill_size, 0.5);
    float fa = smoothstep(-fill_aa, fill_aa, d_fill) * v_fill_a;

    // Composite: fill over stroke (matches original two-pass alpha blending)
    // Text pixels (shape 2) take the dedicated text color instead of fill_color.
    vec3 fill_rgb = (v_shape >= 1.5) ? text_color.rgb : fill_color.rgb;
    float combined_a = fa + sa * (1.0 - fa);
    vec3 combined_rgb = (fill_rgb * fa + stroke_color.rgb * sa * (1.0 - fa))
                      / max(combined_a, 0.001);
    frag_color = vec4(combined_rgb, combined_a);
}
@end

@program particle vs_particle fs_particle
