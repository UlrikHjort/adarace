// AdaRace: a driving simulator in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
// Sky colour by height, the sun, and drifting fractal clouds on a high plane.
#version 450 core

in vec2 vNdc;
uniform mat4 uInvViewProj;
uniform vec3 uCamPos;
uniform vec3 uSunDir;
uniform vec3 uSunColor;
uniform vec3 uSkyColor;
uniform vec3 uHorizon;
uniform float uTime;
uniform float uClouds;
uniform float uMist;
out vec4 fragColor;

float hash(vec2 p)
{
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p)
{
    float a = 0.5, s = 0.0;
    for (int i = 0; i < 6; i++) {
        s += a * noise(p);
        p = p * 2.03 + vec2(17.1, 9.3);
        a *= 0.5;
    }
    return s;
}

void main()
{
    vec4 far = uInvViewProj * vec4(vNdc, 0.0001, 1.0);
    vec3 d = normalize(far.xyz / far.w - uCamPos);
    float up = max(d.y, 0.0);
    vec3 col = mix(uHorizon, uSkyColor, pow(up, 0.45));

    float day = clamp(length(uSkyColor) * 1.6, 0.0, 1.0);
    // Stars, where it is dark enough
    if (day < 0.2 && d.y > 0.0 && uClouds < 0.9) {
        vec2 g = d.xz / (abs(d.y) + 0.35) * 170.0;
        float h = hash(floor(g));
        vec2 f = fract(g) - 0.5;
        float star = step(0.985, h) * smoothstep(0.32, 0.0, length(f));
        col += vec3(0.75, 0.8, 1.0) * star * (0.35 + hash(floor(g) + 3.0)) * (1.0 - day * 5.0);
    }
    float s = max(dot(d, uSunDir), 0.0);
    col += uSunColor * (0.10 * pow(s, 8.0) + 0.30 * pow(s, 64.0));
    col += uSunColor * 8.0 * smoothstep(0.9994, 0.99975, s);

    if (d.y > 0.01) {
        vec2 p = d.xz / (d.y + 0.08) * 1.2 + vec2(uTime * 0.002, uTime * 0.0007);
        float n = fbm(p);
        float cover = smoothstep(0.62 - uClouds * 0.28, 0.82, n);
        // Lit on the side of the sun: a second look a little towards it
        float n2 = fbm(p + uSunDir.xz * 0.08);
        float lit = clamp(0.55 + (n - n2) * 3.5, 0.2, 1.0);
        vec3 cloud = uSunColor * lit * 0.55 + uSkyColor * 0.6 + vec3(0.12) * day;
        col = mix(col, cloud, cover * smoothstep(0.01, 0.16, d.y) * 0.92);
    }
    col = mix(col, uHorizon, uMist);
    fragColor = vec4(col, 1.0);
}
