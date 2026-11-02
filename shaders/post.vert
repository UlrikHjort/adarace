#version 450 core
// AdaRace: a driving simulator in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
out vec2 vUV;
uniform vec4 uRect;   // where on the screen, in 0 .. 1 (x, y, width, height)
uniform float uFlip;
void main()
{
    vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
    vUV = vec2(uFlip > 0.5 ? 1.0 - p.x : p.x, p.y);
    vec2 q = uRect.xy + p * uRect.zw;
    gl_Position = vec4(q * 2.0 - 1.0, 0.0, 1.0);
}
