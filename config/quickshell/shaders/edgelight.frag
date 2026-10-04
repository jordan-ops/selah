// Adapted from Nebula shell (GPL-3.0), shaders/edgelight.frag —
// kept as the documented source for the compiled edgelight.frag.qsb beside it.
// Selah re-hinged it onto the BAR PILL: the distance field is the pill's
// rounded rect (barRect, global coordinates, corner radius) instead of the
// screen edge, so the light orbits the bar itself. The ambient wash is
// damped on the inside of the outline so the pill's own notification text
// never gets tinted.
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
    vec4 barRect;
};

// signed distance to the pill's rounded rect: barRect = (x, y, w, h),
// radius = corner radius (negative inside, as usual for an SDF)
float pillSd(vec2 p) {
    vec2 c = barRect.xy + barRect.zw * 0.5;
    vec2 half_ = barRect.zw * 0.5;
    vec2 q = abs(p - c) - (half_ - vec2(radius));
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    float sd = pillSd(p);
    // distance from the outline, measured on both sides — the core band
    // straddles the pill edge; the bleed reaches into the wallpaper
    float e = abs(sd);
    float reach = max(glow * 1.6, thick + 2.0);
    if (e > reach) {
        fragColor = vec4(0.0);
        return;
    }

    // orbit position: 0 = above the pill, clockwise; same convention the
    // screen version used, now around the pill's centre
    vec2 c = barRect.xy + barRect.zw * 0.5;
    vec2 d = p - c;
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
    // ambient wash only outside the outline — inside sits the pill with
    // the notification text; smoothstep softens the cut over ~1.5 px
    float ambient = halo * wash * smoothstep(-1.5, 1.5, sd);

    float a = clamp(light + ambient, 0.0, 1.0);
    vec3 rgb = tint.rgb * a + vec3(spark);
    a = clamp(a + spark, 0.0, 1.0);
    fragColor = vec4(min(rgb, vec3(a)), a) * qt_Opacity;
}
