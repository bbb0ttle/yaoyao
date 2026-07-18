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
in float v_stroke_size;
in float v_fill_size;
in float v_stroke_a;
in float v_fill_a;
in float v_shape;
out vec4 frag_color;

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
