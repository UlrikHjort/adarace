#version 450 core
// AdaRace: a driving simulator in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
in vec4 vColor;
uniform float uPoints;
out vec4 fragColor;
void main()
{
    float a = vColor.a;
    if (uPoints > 0.5) {
        vec2 q = gl_PointCoord - 0.5;
        float d = dot(q, q) * 4.0;
        if (d > 1.0) discard;
        a *= (1.0 - d) * (1.0 - d);
    }
    fragColor = vec4(vColor.rgb * a, a);
}
