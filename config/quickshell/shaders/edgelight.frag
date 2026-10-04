// Adapted from Nebula shell (GPL-3.0), shaders/edgelight.frag —
// kept as the documented source for the compiled edgelight.frag.qsb beside it.
// Compiled: qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 (must match Qt's
// built-in ShaderEffect vertex profile — wider variant sets fail to link)
#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec4 tint;
    float angle;
    float sweep;
    float wash;
    float thick;
    float glow;
    float radius;
    float tailA;
    float tailB;
};

float edgeDistance(vec2 p) {
    vec2 half_ = itemSize * 0.5;
    vec2 q = abs(p - half_) - (half_ - vec2(radius));
    float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    return -sd;
}

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    float e = edgeDistance(p);
    if (e < -1.0) {
        fragColor = vec4(0.0);
        return;
    }
    e = max(e, 0.0);

    vec2 d = p - itemSize * 0.5;
    float t = fract(atan(d.x, -d.y) / 6.28318530718 - angle / 6.28318530718);

    float head = min(tailB + 0.10, 0.99);
    float rise = smoothstep(tailA, tailB, t);
    float fall = 1.0 - smoothstep(head, 1.0, t);
    float mask = rise * fall;
    float hot = 1.0 - smoothstep(0.0, 0.05, abs(t - (tailB + 0.05)));

    float core = 1.0 - smoothstep(thick - 0.75, thick + 0.75, e);
    float soft = exp(-e / max(1.0, glow * 0.28));
    float halo = exp(-e / max(1.0, glow * 0.45));

    float light = mask * sweep * (core + soft * 0.75);
    float spark = hot * mask * sweep * core * 0.55;
    float ambient = halo * wash;

    float a = clamp(light + ambient, 0.0, 1.0);
    vec3 rgb = tint.rgb * a + vec3(spark);
    a = clamp(a + spark, 0.0, 1.0);
    fragColor = vec4(min(rgb, vec3(a)), a) * qt_Opacity;
}
