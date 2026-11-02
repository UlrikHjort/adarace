#version 450 core
// AdaRace: a driving simulator in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
layout(location = 0) in vec3 aPos;
layout(location = 3) in vec3 aMat;
uniform mat4 uLightViewProj;
uniform mat4 uModel;
flat out float vMat;
out vec2 vUV;
void main()
{
    vMat = aMat.x;
    vUV = aMat.yz;
    gl_Position = uLightViewProj * uModel * vec4(aPos, 1.0);
}
