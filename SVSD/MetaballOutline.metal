#include <metal_stdlib>
using namespace metal;

// Film grain, as the comp's noise layer draws it: about 40% of pixels pulled
// 48% of the way to grey (its rgba(102, 102, 102, 0.48) flood through a noise
// threshold). `scale` is the display scale, so the grain is one device pixel.
// Colours arrive premultiplied, so the grey is too.
[[ stitchable ]] half4 grain(float2 position, half4 color, float scale, float amount) {
    float2 cell = floor(position * scale);
    float noise = fract(sin(dot(cell, float2(12.9898f, 78.233f))) * 43758.5453f);
    half speck = half(step(0.6f, noise) * amount);
    half3 grey = half3(0.4h) * color.a;
    return half4(mix(color.rgb, grey, speck), color.a);
}

// MARK: - Watercolour blooms

float bloomHash(float n) {
    return fract(sin(n * 127.1f) * 43758.5453f);
}

float bloomHash2(float2 p) {
    return fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453f);
}

float bloomNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0f - 2.0f * f);
    float a = bloomHash2(i);
    float b = bloomHash2(i + float2(1.0f, 0.0f));
    float c = bloomHash2(i + float2(0.0f, 1.0f));
    float d = bloomHash2(i + float2(1.0f, 1.0f));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float bloomFbm(float2 p) {
    float value = 0.0f;
    float amplitude = 0.5f;
    for (int octave = 0; octave < 4; octave++) {
        value += amplitude * bloomNoise(p);
        p = p * 2.03f + 17.0f;
        amplitude *= 0.5f;
    }
    return value;
}

// The comp's rainbow, a step deeper so it reads as pigment on paper.
constant float3 bloomPigments[6] = {
    float3(0.96f, 0.47f, 0.67f),   // pink
    float3(0.42f, 0.69f, 0.97f),   // blue
    float3(0.40f, 0.85f, 0.65f),   // green
    float3(1.00f, 0.64f, 0.44f),   // peach
    float3(1.00f, 0.86f, 0.42f),   // lemon
    float3(0.68f, 0.54f, 0.95f)    // lavender
};

// Where a bloom can start, as fractions of the screen: round the edges and
// corners, so the middle (logo, tagline, button) only ever gets their reach.
constant float2 bloomAnchors[8] = {
    float2(0.08f, 0.10f), float2(0.92f, 0.18f), float2(0.02f, 0.42f), float2(0.98f, 0.55f),
    float2(0.10f, 0.90f), float2(0.90f, 0.92f), float2(0.50f, -0.02f), float2(0.55f, 1.02f)
};

// The welcome screen's colour as watercolour on paper: washes laid down a
// little at a time, each in two or three pigments that run into each other,
// with edges that are crisp and rimmed in places and feathered in others,
// and pigment settling into the paper's grain. They drift, fade, and new ones
// are laid down elsewhere. Overlaps glaze, each tinting what's under it.
// `color` is the paper.
[[ stitchable ]] half4 watercolorBloom(float2 position, half4 color, float2 size, float time,
                                       float scale, float dark) {
    float shortSide = min(size.x, size.y);
    float2 point = position / shortSide;
    float3 result = float3(color.rgb);

    // The paper: a fine tooth at the pixel, and a softer unevenness under it.
    float tooth = bloomHash2(floor(position * scale));
    float paper = bloomFbm(position / 9.0f);

    const int count = 6;
    const float period = 17.0f;
    for (int index = 0; index < count; index++) {
        float t = time + float(index) * period / float(count) + 4.0f;
        float cycle = floor(t / period);
        float life = fract(t / period);
        float seed = float(index) * 13.37f + cycle * 7.13f;

        float2 anchor = bloomAnchors[int(bloomHash(seed) * 8.0f) % 8];
        float2 center = anchor * size / shortSide
            + (float2(bloomHash(seed + 1.0f), bloomHash(seed + 2.0f)) - 0.5f) * 0.3f
            + (float2(bloomHash(seed + 3.0f), bloomHash(seed + 4.0f)) - 0.5f) * 0.08f * life;
        float reach = 0.5f + 0.32f * bloomHash(seed + 5.0f);
        // Laid down rather than spreading out from a drop: it opens most of
        // the way at once, then creeps.
        float spread = 0.62f + 0.38f * (1.0f - pow(1.0f - life, 2.0f));
        float radius = reach * spread;
        float strength = smoothstep(0.0f, 0.18f, life) * (1.0f - smoothstep(0.5f, 0.95f, life));

        float2 offset = point - center;
        float distance = length(offset) / radius;
        if (distance > 1.4f || strength <= 0.0f) { continue; }

        // A ragged edge, and how hard it is changes as you go round: crisp
        // with a pooled rim in some places, feathered out in others.
        float2 unit = offset / radius;
        float edge = bloomFbm(unit * 1.8f + seed + time * 0.02f);
        distance *= 1.0f + 0.36f * (edge - 0.5f);
        float hardness = smoothstep(0.35f, 0.7f, bloomFbm(unit * 1.1f + seed * 2.3f + 40.0f));
        float softEdge = mix(0.42f, 0.035f, hardness);
        float body = 1.0f - smoothstep(1.0f - softEdge, 1.0f, distance);
        float rim = exp(-pow((distance - (1.0f - softEdge * 0.5f)) / 0.05f, 2.0f)) * hardness;
        float mottle = 0.82f + 0.36f * bloomFbm(offset * 6.0f + seed * 3.1f);
        float density = strength * (0.44f * body * mottle + 0.3f * rim);
        // Pigment settles in the paper: grainy, heavier in its hollows.
        density *= 0.62f + 0.5f * paper + 0.36f * (tooth - 0.5f);
        density += strength * body * step(0.86f, tooth) * 0.07f;
        density = max(density, 0.0f);

        // Two or three pigments, running into each other across the wash.
        float3 first = bloomPigments[int(bloomHash(seed + 6.0f) * 6.0f) % 6];
        float3 second = bloomPigments[int(bloomHash(seed + 7.0f) * 6.0f) % 6];
        float3 third = bloomHash(seed + 8.0f) > 0.5f
            ? bloomPigments[int(bloomHash(seed + 9.0f) * 6.0f) % 6] : second;
        float angle = bloomHash(seed + 10.0f) * 6.2832f;
        float along = clamp(dot(unit, float2(cos(angle), sin(angle))) * 0.5f + 0.5f
            + 0.12f * (edge - 0.5f), 0.0f, 1.0f);
        float3 pigment = along < 0.5f
            ? mix(first, second, smoothstep(0.0f, 0.5f, along))
            : mix(second, third, smoothstep(0.5f, 1.0f, along));

        if (dark > 0.5f) {
            result = mix(result, pigment * 0.8f, density * 0.75f);
        } else {
            result *= 1.0f - density * (1.0f - pigment);
        }
    }
    // The bare paper has a little tooth too.
    result *= 1.0f - 0.022f * (paper - 0.5f) - 0.012f * (tooth - 0.5f);
    return half4(half3(result), color.a);
}
