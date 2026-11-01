// AdaRace: a driving simulator in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
// One shader for all that stands in daylight; the material number says how
// a surface is painted.  Output is linear light, tone mapped afterwards.
#version 450 core

in vec3 vPos;
in vec3 vNormal;
in vec3 vColor;
flat in float vMat;
in vec2 vUV;

uniform vec3 uCamPos;
uniform vec3 uSunDir;
uniform vec3 uSunColor;
uniform vec3 uSkyColor;
uniform vec3 uHorizon;
uniform float uFog;
uniform vec3 uPaint;
uniform float uBrake;
uniform float uAlpha;
uniform float uShadows;
uniform float uGrain;
uniform float uForest;
uniform float uWet;
uniform float uSnow;
uniform float uSeason;      // 0 summer, 1 autumn, 2 winter, 3 spring
uniform float uCarV;
uniform float uHeadOn;
uniform int uHeadN;
uniform float uHeadPower;
uniform vec3 uHeadPos[8];
uniform vec3 uHeadDir[8];

uniform sampler2D uAsphalt;
uniform sampler2D uGrass;
uniform sampler2D uGravel;
uniform sampler2D uLeaves;
uniform sampler2D uNeedles;

uniform mat4 uShadowNear;
uniform mat4 uShadowFar;
uniform sampler2DShadow uShadowMapNear;
uniform sampler2DShadow uShadowMapFar;

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
    for (int i = 0; i < 4; i++) {
        s += a * noise(p);
        p = p * 2.03 + vec2(17.1, 9.3);
        a *= 0.5;
    }
    return s;
}

float pcf(sampler2DShadow map, vec3 c, float texel)
{
    float s = 0.0;
    for (int x = -1; x <= 1; x++)
        for (int y = -1; y <= 1; y++)
            s += texture(map, vec3(c.xy + vec2(x, y) * texel, c.z));
    return s / 9.0;
}

float sunShadow(vec3 n)
{
    if (uShadows < 0.5) return 1.0;
    float slope = 1.0 - max(dot(n, uSunDir), 0.0);
    vec4 a = uShadowNear * vec4(vPos + n * (0.02 + 0.05 * slope), 1.0);
    vec3 ca = a.xyz / a.w;
    if (all(greaterThan(ca.xy, vec2(0.01))) && all(lessThan(ca.xy, vec2(0.99))) && ca.z < 1.0)
        return pcf(uShadowMapNear, vec3(ca.xy, ca.z - 0.0003), 1.0 / 4096.0);
    vec4 b = uShadowFar * vec4(vPos + n * (0.12 + 0.3 * slope), 1.0);
    vec3 cb = b.xyz / b.w;
    if (all(greaterThan(cb.xy, vec2(0.005))) && all(lessThan(cb.xy, vec2(0.995))) && cb.z < 1.0)
        return pcf(uShadowMapFar, vec3(cb.xy, cb.z - 0.0005), 1.0 / 4096.0);
    return 1.0;
}

// The slope of a height held in a texture's alpha: bends the normal
vec3 bump(sampler2D map, vec2 uv, vec3 n, float strength)
{
    vec2 e = vec2(1.5) / vec2(textureSize(map, 0));
    float h = texture(map, uv).a;
    vec2 g = vec2(texture(map, uv + vec2(e.x, 0.0)).a - h,
                  texture(map, uv + vec2(0.0, e.y)).a - h);
    return normalize(n - strength * vec3(g.x, 0.0, g.y));
}

void main()
{
    float mat = vMat;
    vec3 N = normalize(vNormal);
    vec3 V = uCamPos - vPos;
    float dist = length(V);
    V /= dist;

    // The driving line: dashes, lit by themselves, by the speed against it
    if (mat == 19.0) {
        if (fract(vUV.x / 6.0) > 0.6) discard;
        float over = uCarV - vColor.r;
        vec3 c = over > 3.0 ? vec3(1.0, 0.04, 0.03)
               : over > -2.0 ? vec3(0.95, 0.62, 0.04)
               : vec3(0.05, 0.62, 0.12);
        float a = uAlpha * (1.0 - smoothstep(110.0, 210.0, dist));
        fragColor = vec4(c * a, a);
        return;
    }

    // How much daylight there is, for what light reflects up
    float day = clamp(length(uSkyColor) * 1.6, 0.03, 1.0);
    if (dot(N, V) < 0.0 && mat == 12.0) N = -N;

    vec3 albedo = vColor;
    float gloss = 0.0;     // specular strength
    float shine = 32.0;
    float fres = 0.0;      // sky reflection at grazing angles
    vec3 glow = vec3(0.0);

    // Fine detail fades out in the distance, or it would shimmer
    float detail = clamp(1.0 - dist / 160.0, 0.0, 1.0);

    if (mat == 1.0) {               // grass, and gravel in the traps
        vec2 p = vPos.xz;
        float big = fbm(p / 70.0);
        float mid = fbm(p / 9.0 + 31.0);
        // Two scales turned against each other hide the repeat of the tile
        vec2 q = mat2(0.83, 0.56, -0.56, 0.83) * p;
        vec3 near = texture(uGrass, p / 3.7).rgb;
        vec3 wide = texture(uGrass, q / 19.0).rgb;
        vec3 grass = mix(wide, near * 1.05, 0.65);
        // Greener in the hollows, dry and yellow on the patches between
        vec3 tint = mix(vec3(0.82, 0.92, 0.72), vec3(1.18, 1.06, 0.72), smoothstep(0.42, 0.72, big));
        grass *= tint * (0.72 + 0.56 * mid) * 1.25;
        // Mown stripes on the flat near the circuit
        float stripes = smoothstep(0.42, 0.58, fract(dot(p, vec2(0.70, 0.71)) / 11.0));
        if (uSeason == 1.0) grass *= vec3(1.3, 1.0, 0.62);
        if (uSeason == 3.0) {
            grass *= vec3(0.9, 1.2, 0.85);
            // Flowers, up close
            float f = noise(p * 9.0);
            if (f > 0.86 && detail > 0.3)
                grass = mix(grass, hash(floor(p * 3.0)) > 0.5 ? vec3(0.8, 0.72, 0.1) : vec3(0.75, 0.75, 0.72),
                            detail * smoothstep(0.86, 0.9, f));
        }
        grass *= 1.0 + 0.05 * stripes * (1.0 - uForest) * clamp(1.0 - (vPos.y - 10.0) / 400.0, 0.5, 1.0);
        if (uForest > 0.5) {
            // No lawn in a wood: moss, needles and bare brown earth in patches
            vec3 earth = texture(uGravel, q / 5.0).rgb * vec3(0.42, 0.32, 0.22);
            vec3 moss = grass * vec3(0.62, 0.68, 0.42);
            float bare = smoothstep(0.40, 0.62, fbm(p / 13.0 + 5.0) + 0.25 * (noise(p * 1.1) - 0.5));
            grass = mix(moss, earth, bare * 0.8);
        }
        vec3 gravel = mix(texture(uGravel, p / 2.6).rgb, texture(uGravel, q / 11.0).rgb, 0.45)
                    * (0.62 + 0.42 * big);
        float g = smoothstep(0.35, 0.65, vColor.r + (noise(p / 1.3) - 0.5) * 0.3);
        albedo = mix(grass, gravel, g);
        vec3 bumped = g > 0.5 ? bump(uGravel, p / 2.6, N, 1.2 * detail)
                              : bump(uGrass, p / 3.7, N, 0.9 * detail);
        N = mix(N, bumped, 0.8);
        // Far hills go blue-green
        float far = clamp(dist / 9000.0, 0.0, 1.0);
        albedo = mix(albedo, vec3(0.05, 0.085, 0.05), far);
    } else if (mat == 2.0) {        // asphalt
        vec2 p = vPos.xz;
        vec3 fine = texture(uAsphalt, p / 2.3).rgb;
        vec3 coarse = texture(uAsphalt, vec2(p.y, -p.x) / 9.7).rgb;
        float patchy = fbm(vUV * vec2(0.03, 0.2));
        float tone = mix(0.72, 1.22, patchy);
        vec3 surf = mix(coarse, fine, 0.7) * 1.25 * tone;
        // Rubber laid down along the racing line
        float rub = vColor.r * (0.75 + 0.35 * noise(vUV * vec2(0.12, 1.6)));
        surf *= 1.0 - 0.5 * clamp(rub, 0.0, 1.0);
        albedo = surf;
        N = bump(uAsphalt, p / 2.3, N, 0.55 * detail * (1.0 - 0.6 * clamp(rub, 0.0, 1.0)));
        gloss = 0.05 + 0.13 * clamp(rub, 0.0, 1.0);
        shine = 22.0;
        fres = 0.14 + 0.1 * clamp(rub, 0.0, 1.0);
        // White lines down both edges, worn in places
        float e = min(vColor.g, vColor.b);
        float w = fwidth(e);
        float line = 1.0 - smoothstep(0.075 - w, 0.075 + w, abs(e - 0.22));
        float worn = 0.72 + 0.28 * noise(p * 3.0);
        albedo = mix(albedo, vec3(0.58, 0.58, 0.55) * worn, line * 0.92);
        // Seams in the tarmac, and the snakes of tar that seal the cracks
        float seam = 1.0 - smoothstep(0.0, 0.03 + w, abs(vUV.y - 0.6 - 0.4 * sin(vUV.x * 0.003)));
        albedo *= 1.0 - 0.3 * seam * detail;
        if (detail > 0.0) {
            float crack = abs(fbm(p / 5.5 + 7.0) - 0.5);
            float mask = smoothstep(0.55, 0.68, fbm(p / 31.0));
            float cw = 0.006 + fwidth(crack);
            albedo *= 1.0 - 0.72 * (1.0 - smoothstep(0.0, cw, crack)) * mask * detail;
        }
    } else if (mat == 18.0) {       // a gravel road through the woods
        vec2 p = vPos.xz;
        float e = min(vColor.g, vColor.b);
        // A frayed edge: the grass comes in over it
        float fray = 0.25 + 0.7 * noise(p * 0.8) + 0.35 * noise(p * 3.7);
        if (e < fray - 0.4) discard;
        vec3 fine = texture(uGravel, p / 2.2).rgb;
        vec3 coarse = texture(uGravel, vec2(p.y, -p.x) / 8.3).rgb;
        vec3 road = mix(coarse, fine, 0.6) * vec3(1.05, 0.98, 0.86);
        // Two wheel tracks packed dark and smooth, loose stones thrown between and outside
        float across = vUV.y;
        float ruts = exp(-pow((abs(across) - 0.85) / 0.45, 2.0));
        float loose = fbm(p / 4.0);
        road *= mix(0.92 + 0.3 * loose, 0.62, ruts * 0.8);
        // Greener and darker to the very edge
        road = mix(mix(road, vec3(0.05, 0.075, 0.025), 0.55), road, smoothstep(0.0, 0.9, e));
        albedo = road;
        N = bump(uGravel, p / 2.2, N, (1.1 - 0.7 * ruts) * detail);
        gloss = 0.02;
    } else if (mat == 3.0) {        // kerb
        float band = step(0.5, fract(vUV.x / 6.0));
        albedo = mix(vec3(0.62, 0.03, 0.02), vec3(0.72), band);
        float rib = 0.82 + 0.18 * abs(fract(vUV.x / 1.5) - 0.5) * 2.0;
        albedo *= rib;
        gloss = 0.1;
    } else if (mat == 5.0) {        // car paint
        albedo = uPaint;
        if (vColor.b > 0.5) {
            // On the flanks: UV is along the car and height, RG the axles
            float d = min(length(vUV - vec2(vColor.r, 0.34)), length(vUV - vec2(vColor.g, 0.34)));
            if (d < 0.40) discard;
            float aa = fwidth(d);
            float lip = 1.0 - smoothstep(0.012, 0.022 + aa, d - 0.40);
            // Door shut lines and a handle
            float shut = min(abs(vUV.x + 0.62), abs(vUV.x - 0.74));
            float sw = fwidth(vUV.x);
            float seam = (1.0 - smoothstep(0.004, 0.008 + sw, shut)) * step(0.22, vUV.y) * step(vUV.y, 0.87);
            float sill = (1.0 - smoothstep(0.004, 0.008 + fwidth(vUV.y), abs(vUV.y - 0.27)))
                       * step(-0.62, vUV.x) * step(vUV.x, 0.74);
            float handle = step(abs(vUV.x - 0.56), 0.075) * step(abs(vUV.y - 0.72), 0.012);
            float dark = max(max(seam, sill), max(lip * 0.75, handle * 0.6));
            albedo *= 1.0 - dark;
            gloss *= 1.0;
            N = normalize(N + vec3(0.0, 0.25 * handle, 0.0));
        }
        gloss = 0.9;
        shine = 180.0;
        fres = 0.55;
    } else if (mat == 6.0) {        // glass
        // From inside the car the bodywork's glass only gets in the way
        if (uGrain < -0.5) discard;
        gloss = 1.0;
        shine = 300.0;
        fres = 0.9;
    } else if (mat == 7.0) {        // rubber
        gloss = 0.05;
        shine = 12.0;
    } else if (mat == 8.0) {        // lamp, brighter with the brake
        glow = vColor * (0.35 + 7.0 * uBrake);
    } else if (mat == 9.0 || mat == 10.0) {   // foliage cards
        vec4 t = mat == 9.0 ? texture(uLeaves, vUV) : texture(uNeedles, vUV);
        float tree = hash(floor(vPos.xz / 9.0));
        // Winter: the broadleaves have let go of nearly all
        if (t.a < (uSeason == 2.0 && mat == 9.0 ? 0.93 : 0.42)) discard;
        albedo = vColor * t.rgb * 0.62;
        if (mat == 9.0) {
            float g = dot(t.rgb, vec3(0.33)) * 1.1;
            if (uSeason == 1.0) {
                vec3 turn = tree < 0.3 ? vec3(0.62, 0.10, 0.03)
                          : tree < 0.7 ? vec3(0.78, 0.34, 0.04)
                          : vec3(0.72, 0.56, 0.07);
                albedo = mix(albedo, turn * g, 0.9);
            } else if (uSeason == 2.0) {
                albedo = vec3(0.16, 0.12, 0.08) * g;
            } else if (uSeason == 3.0) {
                albedo = tree < 0.18 ? mix(albedo, vec3(0.85, 0.62, 0.72) * g, 0.85)
                                     : albedo * vec3(1.05, 1.2, 0.9);
            }
        }
    } else if (mat == 11.0) {       // metal
        gloss = 0.7;
        shine = 70.0;
        fres = 0.5;
    } else if (mat == 12.0) {       // wire fence
        // Holes while they can be told apart; further off, a thin veil
        vec2 uv = vUV * 7.0;
        vec2 q = abs(fract(uv) - 0.5);
        float wire = max(step(0.44, q.x), step(0.44, q.y));
        float spread = length(fwidth(uv));
        float keep = mix(wire, 0.05, smoothstep(0.12, 0.35, spread));
        if (hash(floor(gl_FragCoord.xy)) > keep) discard;
        // Far off the wires are a shadow on what is behind, never sparkle
        albedo *= mix(1.0, 0.28, smoothstep(0.12, 0.35, spread));
    } else if (mat == 13.0) {       // spectators
        vec2 cell = floor(vUV * vec2(2.2, 2.5));
        float pick = hash(cell);
        vec3 shirt = 0.5 + 0.5 * cos(6.28 * (pick * 3.0 + vec3(0.0, 0.33, 0.67)));
        shirt = mix(vec3(0.3), shirt, 0.45) * 0.55;
        vec2 seat = fract(vUV * vec2(2.2, 2.5));
        float person = smoothstep(0.45, 0.35, abs(seat.x - 0.5));
        albedo = mix(vec3(0.07), shirt, person * step(0.2, pick));
    } else if (mat == 14.0) {       // chequers
        vec2 c = floor(vUV / 0.6);
        albedo = vec3(mod(c.x + c.y, 2.0) * 0.8 + 0.02);
    } else if (mat == 15.0) {       // lit by itself
        glow = vColor * 1.6;
        albedo = vec3(0.0);
    } else if (mat == 16.0) {       // corrugated steel
        // Two grooves along the rail, in the 0.48 m of its height
        float wave = cos(vUV.y * 6.2832 / 0.24);
        vec3 up = vec3(0.0, 1.0, 0.0);
        N = normalize(N + up * 0.55 * wave);
        albedo *= 0.8 + 0.14 * noise(vPos.xz * 0.6) + 0.06 * wave;
        gloss = 0.55;
        shine = 45.0;
        fres = 0.25;
    } else if (mat == 17.0) {       // an advert: bars of a made-up name
        // Blocky letters of a name, 5 by 5 cells, every 14 m
        float word = floor(vUV.x / 14.0);
        float along = mod(vUV.x, 14.0) - 2.0;
        float letter = floor(along / 1.0);
        vec2 inLetter = vec2(fract(along / 1.0) * 6.0, (vUV.y - 0.12) / 0.10);
        vec2 c5 = floor(inLetter);
        float ink = 0.0;
        if (along > 0.0 && along < 8.0 && c5.x < 5.0 && c5.y >= 0.0 && c5.y < 5.0) {
            float h = hash(vec2(letter + 19.0 * word, floor(c5.y / 2.0) + 3.0 * floor(c5.x / 2.0)));
            // Every letter has its stems; the cross bars vary
            ink = (c5.x == 0.0 || mod(c5.y, 2.0) == 0.0) ? step(0.22, h) : step(0.72, h);
        }
        float lum = dot(vColor, vec3(0.3, 0.6, 0.1));
        albedo = mix(vColor, lum > 0.45 ? vec3(0.03) : vec3(0.62), ink);
        gloss = 0.12;
    }

    // Rain: dark, shining ground and standing water
    if (uWet > 0.0 && uGrain > 0.5) {
        vec2 wp = vPos.xz;
        if (mat == 2.0 || mat == 18.0) {
            float puddle = smoothstep(0.54, 0.66, fbm(wp / (mat == 2.0 ? 7.0 : 3.5)) + 0.08 * (mat == 18.0 ? 1.0 : 0.0));
            albedo *= mix(0.55, 0.32, puddle);
            N = normalize(mix(N, vec3(0.0, 1.0, 0.0), puddle));
            gloss = max(gloss, mix(0.5, 1.0, puddle) * uWet);
            shine = mix(60.0, 300.0, puddle);
            fres = max(fres, mix(0.35, 0.95, puddle) * uWet);
        } else if (mat == 1.0) {
            albedo *= 0.72;
            fres = max(fres, 0.05);
        } else if (mat == 0.0 || mat == 3.0 || mat == 16.0 || mat == 17.0) {
            albedo *= 0.75;
            gloss = max(gloss, 0.3);
            fres = max(fres, 0.15);
        }
    }
    if (uWet > 0.0 && (mat == 9.0 || mat == 10.0)) albedo *= 0.75;

    // Snow: on whatever faces up
    if (uSnow > 0.5) {
        vec2 sp = vPos.xz;
        vec3 white = vec3(0.66, 0.68, 0.72);
        float drift = 0.9 + 0.1 * fbm(sp / 3.0);
        if (mat == 1.0) {
            float through = smoothstep(0.62, 0.70, fbm(sp / 11.0) + 0.1 * noise(sp * 2.0));
            albedo = mix(white * drift, albedo * 0.7, through * 0.3);
            N = normalize(mix(vec3(0.0, 1.0, 0.0), N, 0.4));
            gloss = 0.08;
            shine = 90.0;
        } else if (mat == 18.0) {
            float ruts = exp(-pow((abs(vUV.y) - 0.85) / 0.5, 2.0));
            albedo = mix(white * drift, albedo * 0.55 + vec3(0.14, 0.15, 0.17), ruts * 0.75);
            gloss = max(gloss, 0.18);
            shine = 70.0;
            fres = max(fres, 0.12);
        } else if (mat == 2.0) {
            float e = min(vColor.g, vColor.b);
            float bank = 1.0 - smoothstep(0.4, 1.9, e + 1.0 * noise(sp * 0.7));
            albedo = mix(albedo * 0.72, white * drift, bank);
            gloss = max(gloss, 0.4 * (1.0 - bank));
            fres = max(fres, 0.3 * (1.0 - bank));
        } else if (mat == 3.0) {
            albedo = mix(albedo, white, 0.55 * noise(sp * 1.5));
        } else if (mat == 10.0 || mat == 9.0) {
            // Lying on the top of each branch
            float top = smoothstep(0.42, 0.8, N.y + 0.3 * noise(vPos.xz * 2.0 + vPos.y));
            float on_branch = dot(albedo, vec3(0.33));
            albedo = mix(albedo, white * (0.55 + 3.0 * on_branch), top * (mat == 10.0 ? 0.85 : 0.3));
        } else if (mat == 0.0 && uGrain > 0.5 && N.y > 0.75) {
            albedo = white * drift;
        }
    }

    // Trim inside and on the cars: a fine leathery grain in its own metres
    if (uGrain < 0.5 && mat == 0.0 && detail > 0.9)
        albedo *= 0.94 + 0.12 * noise(vUV * 240.0);

    // Plain surfaces of the circuit: weather and wear, no two metres the same
    if (uGrain > 0.5 && (mat == 0.0 || mat == 3.0 || mat == 16.0)) {
        vec3 an = abs(N);
        vec2 gp = an.y > 0.7 ? vPos.xz : (an.x > an.z ? vPos.zy : vPos.xy);
        float g = texture(uGravel, gp / 3.1).a;
        float stain = fbm(gp / 6.0);
        albedo *= (0.84 + 0.3 * g) * (0.82 + 0.36 * stain);
    }

    float shadow = sunShadow(N);
    float NdotL = max(dot(N, uSunDir), 0.0);
    bool leafy = mat == 9.0 || mat == 10.0;
    if (leafy) {
        // Wrapped round the crown, and the sun glowing through from behind
        NdotL = clamp(dot(N, uSunDir) * 0.6 + 0.4, 0.0, 1.0);
        NdotL += 0.35 * pow(max(dot(-V, uSunDir), 0.0), 4.0);
    }
    vec3 H = normalize(uSunDir + V);
    float spec = min(gloss * pow(max(dot(N, H), 0.0), shine) * (shine + 8.0) / 60.0, 1.2);
    // The sky from above, the ground's bounce from below
    vec3 ambient = mix(vec3(0.10, 0.11, 0.09) * day, uSkyColor * 1.1, 0.5 + 0.5 * N.y);
    vec3 light = uSunColor * NdotL * shadow;
    vec3 color = albedo * (light + ambient) + uSunColor * spec * shadow * step(0.001, NdotL) + glow;

    // Headlamps: a pool of light down the road, and the glare off anything wet
    if (uHeadOn > 0.5) {
        for (int i = 0; i < uHeadN; i++) {
            vec3 toLamp = uHeadPos[i] - vPos;
            float d = length(toLamp);
            toLamp /= d;
            float along = dot(-toLamp, uHeadDir[i]);
            float cone = smoothstep(0.86, 0.985, along);
            if (cone > 0.0) {
                float power = min(2.4, (i == 0 ? uHeadPower : 0.8) * 650.0 / (d * d + 60.0));
                float facing = leafy ? 0.65 : max(dot(N, toLamp), 0.0) + 0.12;
                vec3 lamp = vec3(1.0, 0.95, 0.82) * cone * power;
                color += albedo * lamp * facing;
                vec3 HL = normalize(toLamp + V);
                color += lamp * min(gloss * pow(max(dot(N, HL), 0.0), shine) * 0.25, 0.8);
            }
        }
    }

    if (fres > 0.0) {
        vec3 R = reflect(-V, N);
        float up = clamp(R.y, 0.0, 1.0);
        vec3 sky = mix(uHorizon, uSkyColor * 1.3, pow(up, 0.5));
        // Below the horizon the ground is seen
        // A dark band of far trees, so that paint has something moving in it
        float tree = 1.0 - smoothstep(0.015, 0.09 + 0.05 * noise(R.xz * 14.0), R.y);
        sky = mix(sky, vec3(0.035, 0.05, 0.03), tree * 0.8);
        sky = mix(vec3(0.05, 0.07, 0.04), sky, smoothstep(-0.05, 0.03, R.y));
        float f = pow(1.0 - max(dot(N, V), 0.0), 5.0);
        color += sky * (0.04 + 0.96 * f) * fres;
    }

    float fog = 1.0 - exp(-uFog * dist);
    vec3 sunward = uHorizon + uSunColor * 0.08 * pow(max(dot(-V, uSunDir), 0.0), 8.0);
    color = mix(color, sunward, fog);
    fragColor = vec4(color * uAlpha, uAlpha);
}
