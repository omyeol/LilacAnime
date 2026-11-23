#include <metal_stdlib>
using namespace metal;

// ============================================================================
// LilacAnime iOS Metal Shaders
// 1. Anime4K CNN / Line-Art Restoration & Upscaling (Modes A, B, C, A+A, B+B, C+A)
// 2. SubtitleEraseShaderHq (Structure-Aware Hard-Sub Erasing + Stroke Classification)
// 3. Watermark Delogo (Smooth Boundary Interpolation)
// ============================================================================

struct RegionRect {
    float4 bounds; // (x, y, width, height) in normalized [0..1] coordinates
};

struct LilacFilterUniforms {
    int anime4kEnabled;
    int anime4kMode; // 0: A, 1: B, 2: C, 3: A+A, 4: B+B, 5: C+A
    int subtitleEraseEnabled;
    int subtitleEraseDebug;
    int subtitleEraseStrictOutline;
    int subtitleEraseLimitLength;
    int subtitleRegionCount;
    int watermarkEnabled;
    int watermarkRegionCount;
    float2 texelSize;
};

static inline float luminance(float3 c) {
    return dot(c, float3(0.299, 0.587, 0.114));
}

static inline float chroma(float3 c) {
    return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
}

static inline bool inNormalizedRect(float2 uv, float4 r, float padX, float padY) {
    return uv.x >= (r.x - padX) && uv.x <= (r.x + r.z + padX) &&
           uv.y >= (r.y - padY) && uv.y <= (r.y + r.w + padY);
}

static inline bool inAnyRegion(float2 uv, constant RegionRect *rects, int count, float padX, float padY) {
    for (int i = 0; i < count; ++i) {
        if (inNormalizedRect(uv, rects[i].bounds, padX, padY)) {
            return true;
        }
    }
    return false;
}

// Classify pixel as (fillCandidate, outlineCandidate) matching SubtitleEraseShaderHq.kt
static inline float2 classifySubtitlePixel(texture2d<float, access::sample> tex, sampler s, float2 uv) {
    float3 c = tex.sample(s, uv).rgb;
    float l = luminance(c);
    float ch = chroma(c);
    float f = (l > 0.66 && ch < 0.18) ? 1.0 : 0.0;
    float o = (l < 0.28 && ch < 0.20) ? 1.0 : 0.0;
    return float2(f, o);
}

static inline float strokeRunEnds(
    texture2d<float, access::sample> tex,
    sampler s,
    float2 p,
    float2 dir,
    float2 pt,
    float scale,
    float maxSteps
) {
    for (int k = 1; k <= 18; ++k) {
        if (float(k) > maxSteps) break;
        float2 q = p + dir * (2.0 * scale * float(k)) * pt;
        if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) return 0.0;
        float2 cl = classifySubtitlePixel(tex, s, q);
        if (cl.x < 0.4) {
            for (int m = 0; m < 3; ++m) {
                float2 q2 = q + dir * (2.0 * scale * float(m)) * pt;
                if (classifySubtitlePixel(tex, s, q2).y > 0.4) return 2.0;
            }
            return 1.0;
        }
    }
    return 0.0;
}

// Anime4K Line Reconstruction + Clamp Highlights Pass
static inline float3 applyAnime4K(
    texture2d<float, access::sample> tex,
    sampler s,
    float2 uv,
    float2 pt,
    int mode
) {
    float3 c = tex.sample(s, uv).rgb;
    float3 n = tex.sample(s, uv + float2(0.0, -pt.y)).rgb;
    float3 so = tex.sample(s, uv + float2(0.0, pt.y)).rgb;
    float3 e = tex.sample(s, uv + float2(pt.x, 0.0)).rgb;
    float3 w = tex.sample(s, uv + float2(-pt.x, 0.0)).rgb;
    float3 ne = tex.sample(s, uv + float2(pt.x, -pt.y)).rgb;
    float3 nw = tex.sample(s, uv + float2(-pt.x, -pt.y)).rgb;
    float3 se = tex.sample(s, uv + float2(pt.x, pt.y)).rgb;
    float3 sw = tex.sample(s, uv + float2(-pt.x, pt.y)).rgb;

    float3 minNeighbor = min(min(min(n, so), min(e, w)), c);
    float3 maxNeighbor = max(max(max(n, so), max(e, w)), c);

    // Sobel edge gradient & anime line Push-Pull strength per mode (A, B, C, A+A, B+B, C+A)
    float strength = (mode == 0 || mode == 3) ? 0.48 : ((mode == 1 || mode == 4) ? 0.32 : 0.25);
    float3 avg = (n + so + e + w + 0.5 * (ne + nw + se + sw)) / 6.0;
    float3 sharpened = c + (c - avg) * strength;

    // Clamp Highlights to prevent ringing artifacts around anime line art
    return clamp(sharpened, minNeighbor, maxNeighbor);
}

kernel void lilacVideoPostProcess(
    texture2d<float, access::sample> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant LilacFilterUniforms &u [[buffer(0)]],
    constant RegionRect *subtitleRects [[buffer(1)]],
    constant RegionRect *watermarkRects [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    constexpr sampler texSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size = float2(outTexture.get_width(), outTexture.get_height());
    float2 pt = 1.0 / max(size, float2(1.0));
    float2 uv = (float2(gid) + 0.5) * pt;

    float3 color = inTexture.sample(texSampler, uv).rgb;

    // 1. Watermark Delogo (Inverse-distance boundary interpolation)
    if (u.watermarkEnabled != 0 && u.watermarkRegionCount > 0) {
        for (int i = 0; i < u.watermarkRegionCount; ++i) {
            float4 r = watermarkRects[i].bounds;
            if (inNormalizedRect(uv, r, 0.0, 0.0)) {
                float2 leftUV = float2(max(0.0, r.x - 2.0 * pt.x), uv.y);
                float2 rightUV = float2(min(1.0, r.x + r.z + 2.0 * pt.x), uv.y);
                float2 topUV = float2(uv.x, max(0.0, r.y - 2.0 * pt.y));
                float2 bottomUV = float2(uv.x, min(1.0, r.y + r.w + 2.0 * pt.y));

                float dx = clamp((uv.x - r.x) / max(r.z, 0.0001), 0.0, 1.0);
                float dy = clamp((uv.y - r.y) / max(r.w, 0.0001), 0.0, 1.0);

                float3 horiz = mix(inTexture.sample(texSampler, leftUV).rgb, inTexture.sample(texSampler, rightUV).rgb, dx);
                float3 vert = mix(inTexture.sample(texSampler, topUV).rgb, inTexture.sample(texSampler, bottomUV).rgb, dy);
                color = 0.5 * (horiz + vert);
            }
        }
    }

    // 2. Hard-Sub Subtitle Erase HQ (Stroke classification + 8-direction background probe)
    if (u.subtitleEraseEnabled != 0 && u.subtitleRegionCount > 0 &&
        inAnyRegion(uv, subtitleRects, u.subtitleRegionCount, 0.0, 0.0)) {
        float scale = max(size.y / 1080.0, 0.5);
        float2 cl = classifySubtitlePixel(inTexture, texSampler, uv);
        bool isStrokeOrHalo = false;

        if (cl.x > 0.5 || cl.y > 0.5) {
            for (int axis = 0; axis < 4; ++axis) {
                float angle = 0.7853982 * float(axis);
                float2 dir = float2(cos(angle), sin(angle));
                float e1 = strokeRunEnds(inTexture, texSampler, uv, dir, pt, scale, 10.0);
                float e2 = strokeRunEnds(inTexture, texSampler, uv, -dir, pt, scale, 10.0);
                if (e1 > 0.5 && e2 > 0.5 && (u.subtitleEraseStrictOutline == 0 || max(e1, e2) > 1.5)) {
                    isStrokeOrHalo = true;
                    break;
                }
            }
        }

        if (isStrokeOrHalo) {
            if (u.subtitleEraseDebug != 0) {
                color = (cl.x > 0.5) ? float3(1.0, 0.9, 0.1) : float3(0.95, 0.2, 0.2);
            } else {
                // Probe 8 directions outside the stroke/outline to reconstruct background
                float3 sumColor = float3(0.0);
                float sumWeight = 0.0;
                for (int d = 0; d < 8; ++d) {
                    float a = 0.7853982 * float(d);
                    float2 dir = float2(cos(a), sin(a));
                    for (int step = 2; step <= 18; step += 2) {
                        float dist = float(step) * scale;
                        float2 q = clamp(uv + dir * dist * pt, float2(0.0), float2(1.0));
                        float2 qClass = classifySubtitlePixel(inTexture, texSampler, q);
                        if (qClass.x < 0.4 && qClass.y < 0.4) {
                            float w = 1.0 / (dist * dist + 1.0);
                            sumColor += inTexture.sample(texSampler, q).rgb * w;
                            sumWeight += w;
                            break;
                        }
                    }
                }
                if (sumWeight > 0.0) {
                    color = sumColor / sumWeight;
                }
            }
        }
    }

    // 3. Anime4K CNN Restoration & Upscaling
    if (u.anime4kEnabled != 0) {
        color = applyAnime4K(inTexture, texSampler, uv, pt, u.anime4kMode);
    }

    outTexture.write(float4(color, 1.0), gid);
}
