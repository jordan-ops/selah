// Adapted from Nebula shell (GPL-3.0), shaders/themeflip.frag —
// kept as the documented source for the compiled themeflip.frag.qsb beside it.
// Compiled: qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 (must match Qt's
// built-in ShaderEffect vertex profile — wider variant sets fail to link)
#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec2 center;
    float radius;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    float d = distance(qt_TexCoord0 * itemSize, center);
    float keep = smoothstep(radius - 1.5, radius + 1.5, d);
    fragColor = texture(source, qt_TexCoord0) * keep * qt_Opacity;
}
