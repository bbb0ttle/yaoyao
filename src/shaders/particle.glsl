// Particle instancing shader — heart/diamond SDF point sprites.
// One shader for both stroke (drawn first) and fill (drawn second) passes.

@vs vs_particle
layout(binding=0) uniform vs_params {
    mat4 mvp;
};

// Static quad corners: (0,0), (1,0), (0,1), (1,1)
in vec2 quad_corner;

// Per-instance data (see GpuInstance in main.zig):
// x, y: world position of particle center
// size: display radius in pixels
// color: packed RGBA (normalized to [0,1])
// shape: 0.0 = diamond, 1.0 = heart
in vec2 inst_pos;
in float inst_size;
in vec4 inst_color;
in float inst_shape;

out vec2 v_uv;       // local quad coordinate [-1, 1]
out vec4 v_color;    // per-instance color
out float v_size;    // particle size for AA calculation
out float v_shape;   // shape selector

void main() {
    // quad_corner in [0,1], scale to [-1,1] for SDF evaluation
    vec2 local = (quad_corner - 0.5) * 2.0;
    vec2 world = local * inst_size + inst_pos;
    gl_Position = mvp * vec4(world, 0.0, 1.0);
    v_uv = local;
    v_color = inst_color;
    v_size = inst_size;
    v_shape = inst_shape;
}
@end

@fs fs_particle
in vec2 v_uv;
in vec4 v_color;
in float v_size;
in float v_shape;
out vec4 frag_color;

void main() {
    float d;

    if (v_shape < 0.5) {
        // Diamond SDF: |x| + |y| <= 1
        d = 1.0 - (abs(v_uv.x) + abs(v_uv.y));
    } else {
        // Heart SDF: classic implicit heart curve (x^2 + y^2 - 1)^3 - x^2 * y^3 <= 0
        // v_uv is in [-1,1]; shift y to center the heart
        float x = v_uv.x;
        float y = v_uv.y + 0.25;
        float x2 = x * x;
        float y2 = y * y;
        float h = x2 + y2 - 1.0;
        d = -(h * h * h - x2 * y2 * y);
    }

    // Anti-aliased edge: smoothstep over 1 pixel width
    float edge = 1.0 / max(v_size, 0.5);
    float alpha = smoothstep(-edge, edge, d) * v_color.a;
    frag_color = vec4(v_color.rgb, alpha);
}
@end

@program particle vs_particle fs_particle
