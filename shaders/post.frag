// AdaRace: a driving simulator in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
// From the linear light of the scene to the screen: bloom, tone map, grade.
#version 450 core
in vec2 vUV;
uniform sampler2D uScene;
uniform float uVignette;
uniform float uExposure;
uniform float uBloom;
uniform float uRain;
uniform float uTime;
out vec4 fragColor;

vec3 aces(vec3 x)
{
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

// Only what is brighter than white glows
vec3 bright(float lod)
{
    vec2 e = vec2(1.0) / vec2(textureSize(uScene, int(lod)));
    vec3 c = 0.25 * (textureLod(uScene, vUV + e * vec2(0.5, 0.5), lod).rgb
                   + textureLod(uScene, vUV + e * vec2(-0.5, 0.5), lod).rgb
                   + textureLod(uScene, vUV + e * vec2(0.5, -0.5), lod).rgb
                   + textureLod(uScene, vUV + e * vec2(-0.5, -0.5), lod).rgb);
    return max(c * uExposure - 1.3, vec3(0.0));
}

float hash(vec2 p)
{
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// The wiper: an arm from below the screen, swept to and fro
float wiperAngle() { return 0.75 * sin(uTime * 2.6); }

void main()
{
    vec2 uv = vUV;
    float blade = 0.0;
    if (uRain > 0.5) {
        vec2 pivot = vec2(0.42, -0.1);
        vec2 q = (uv - pivot) * vec2(1.78, 1.0);
        float ang = atan(q.x, q.y);
        float w = wiperAngle();
        float reach = length(q);
        blade = (1.0 - smoothstep(0.0025, 0.0055, abs(ang - w) * reach))
              * step(reach, 0.82) * step(0.28, reach);
        // Drops on the glass, older the longer since the blade went by
        float since = fract((uTime * 2.6 / 6.2832) + ang * 0.12);
        vec2 grid = uv * vec2(60.0, 34.0);
        vec2 cell = floor(grid);
        for (int k = 0; k < 2; k++) {
            vec2 ce = cell + float(k) * vec2(7.0, 3.0);
            float h = hash(ce);
            if (h > 0.55) {
                vec2 ctr = vec2(hash(ce + 1.0), hash(ce + 2.0)) - 0.5;
                float rad = 0.16 + 0.22 * hash(ce + 3.0);
                float dd = length(fract(grid) - 0.5 - ctr * 0.5);
                if (dd < rad * since * 1.4)
                    uv += (fract(grid) - 0.5 - ctr * 0.5) * 0.006;
            }
        }
    }
    vec3 c = textureLod(uScene, uv, 0.0).rgb * uExposure;
    if (uBloom > 0.0) {
        vec3 glow = bright(2.0) * 0.30 + bright(3.0) * 0.28 + bright(4.0) * 0.24 + bright(5.0) * 0.18;
        c += min(glow, vec3(4.0)) * 0.22 * uBloom;
    }
    c = mix(c, vec3(0.005), blade);
    c = aces(c);
    // A touch more contrast, and colours a little less like a cartoon
    float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
    c = mix(vec3(luma), c, 0.93);
    c = mix(c, c * c * (3.0 - 2.0 * c), 0.18);
    if (uVignette > 0.0) {
        vec2 q = vUV - 0.5;
        c *= 1.0 - uVignette * dot(q, q) * 1.2;
    }
    fragColor = vec4(pow(c, vec3(1.0 / 2.2)), 1.0);
}
