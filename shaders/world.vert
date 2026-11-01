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
uniform float uDent;

out vec3 vPos;
out vec3 vNormal;
out vec3 vColor;
flat out float vMat;
out vec2 vUV;
out vec3 vLocal;

void main()
{
    // Crumpled where it has been hit: the two ends of the bodywork
    vec3 p = aPos;
    if (uDent > 0.0 && aMat.x == 5.0) {
        float ends = smoothstep(1.2, 2.2, abs(p.z));
        float folds = sin(p.x * 8.0 + 1.0) * sin(p.y * 11.0) * sin(p.z * 6.0 + 2.0);
        p += vec3(0.04 * folds, 0.05 * folds, -sign(p.z) * (0.09 + 0.05 * folds)) * uDent * ends;
    }
    vLocal = p;
    vec4 w = uModel * vec4(p, 1.0);
    vPos = w.xyz;
    vNormal = mat3(uModel) * aNormal;
    vColor = aColor;
    vMat = aMat.x;
    vUV = aMat.yz;
    gl_Position = uViewProj * w;
}
