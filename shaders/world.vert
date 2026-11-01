// AdaRace: a driving simulator in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
#version 450 core

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec3 aColor;
layout(location = 3) in vec3 aMat;   // material, u, v

uniform mat4 uViewProj;
uniform mat4 uModel;

out vec3 vPos;
out vec3 vNormal;
out vec3 vColor;
flat out float vMat;
out vec2 vUV;

void main()
{
    vec4 w = uModel * vec4(aPos, 1.0);
    vPos = w.xyz;
    vNormal = mat3(uModel) * aNormal;
    vColor = aColor;
    vMat = aMat.x;
    vUV = aMat.yz;
    gl_Position = uViewProj * w;
}
