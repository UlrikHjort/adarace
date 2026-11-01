// Skid marks (triangles) and tyre smoke (points)
#version 450 core
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec4 aColor;   // premultiplied in the fragment shader
layout(location = 2) in float aSize;
uniform mat4 uViewProj;
uniform float uPointScale;
out vec4 vColor;
void main()
{
    vColor = aColor;
    gl_Position = uViewProj * vec4(aPos, 1.0);
    gl_PointSize = clamp(aSize * uPointScale / max(gl_Position.w, 0.1), 1.0, 500.0);
}
