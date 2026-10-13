#include <metal_stdlib>
using namespace metal;

// Glass avatar — the Metal twin of prototype/src/coin/coin-shader.js (function by function).
//
// Geometry: a two-sided photo card (radius R) inside a thin sheet of glass of the same radius. The sheet's faces are
// flat over the photo and its edge is a rounded band (an elliptical quarter-round, w = rimWidth wide and
// 2·h = 2·halfThickness thick) that lies INSIDE the photo's circle: the silhouette is exactly the avatar's, nothing
// frames it, and the glass only shows as a lens band along the edge (the photo folds into it), a thin bright edge line
// and the light gliding over the face when it tilts. Units are points, origin at the centre, y up, z toward the
// viewer; the eye sits at z = eyeDistance (CATransform3D m34 = -1/eyeDistance).
//
// Per pixel:
//   1. analytic slab/cylinder entry, sphere tracing of the rounded edge
//   2. Fresnel (Schlick) mix of a soft studio reflection and the refracted ray
//   3. refracted ray → photo card (A front, B back), or through the glass → the cover (with dispersion)
//   4. glass colour (tint denser toward the edge), matte haze and a faint darker line where the lens band begins, sheen,
//      edge line, centred soft shadow, glow
//   5. motion blur: up to 8 yaw samples across the shutter for fast spins
// At glass = 0 the band and thickness collapse, shading fades out and the result is the flat avatar, pixel for pixel.

// Must match GlassCoinUniforms (GlassCoinLayer.swift) member for member: 14 × float4 = 224 bytes. Every member is a
// float4 (16-byte size and alignment in both languages), so there is no implicit padding anywhere.
//
//  #  member      x                  y                z                 w                  GLSL uniforms
//  0  frame0      bounds width (pt)  bounds height    render width (px) render height (px) (canvas size)
//  1  frame1      edge inset (px)    pixels per pt    centre x (pt)     centre y (pt, y↓)  uPxPerPt, uCenterPt
//  2  pose        yaw                pitch            yaw span          samples            uYaw … uSamples
//  3  coin        coinZ              radius R         halfThickness h   glass              uCoinZ … uGlass
//  4  edge        rimWidth w         photo LOD        coinBound         influence          uRimWidth, uPhotoLod, …
//  5  optics      eyeDistance        ior              dispersion        light intensity    uEyeDistance … uLightIntensity
//  6  light       envRotation        edgeBoost        glassTint         glow               uEnvRotation, uEdgeBoost, …
//  7  envLow      rgb                                                   (0)                uEnvLow
//  8  envHigh     rgb                                                   (0)                uEnvHigh
//  9  glassColor  rgb                                                   (0)                uGlassColor
// 10  glowColor   rgb                                                   (0)                uGlowColor
// 11  coverRect   x                  y (top, y↓)      width             height             uCoverRectPt (layer points)
// 12  shadow0     centre x           centre y (y↑)    axis x            axis y             uShadowCenter, uShadowAxes
// 13  shadow1     angle              sigma            strength          (0)                uShadowAngle … uShadowStrength
struct GlassCoinUniforms {
    float4 frame0;
    float4 frame1;
    float4 pose;
    float4 coin;
    float4 edge;
    float4 optics;
    float4 light;
    float4 envLow;
    float4 envHigh;
    float4 glassColor;
    float4 glowColor;
    float4 coverRect;
    float4 shadow0;
    float4 shadow1;
};

struct GlassCoinGeometry {
    float radius;
    float halfThickness;
    float rimWidth;
};

constant static float2 glassCoinQuadVertices[6] = {
    float2(0.0, 0.0),
    float2(1.0, 0.0),
    float2(0.0, 1.0),
    float2(1.0, 0.0),
    float2(0.0, 1.0),
    float2(1.0, 1.0)
};

struct GlassCoinVertexOut {
    float4 position [[position]];
    float2 uv;
};

// `rect` is the allocation in normalized surface coordinates, y pointing up; uv.y = 0 is the top edge.
vertex GlassCoinVertexOut glassCoinVertex(
    constant float4 &rect [[ buffer(0) ]],
    unsigned int vid [[ vertex_id ]]
) {
    float2 quadVertex = glassCoinQuadVertices[vid];
    GlassCoinVertexOut out;
    float x = rect.x + quadVertex.x * rect.z;
    float y = rect.y + (1.0 - quadVertex.y) * rect.w;
    out.position = float4(-1.0 + x * 2.0, -1.0 + y * 2.0, 0.0, 1.0);
    out.uv = quadVertex;
    return out;
}

// ------------------------------------------------------------------ geometry

// sdCoin: flat faces at z = ±h over r < R − w; the edge is the ellipse ((r − (R − w))/w)² + (z/h)² = 1.
// The radial axis is scaled by h/w ≤ 1 to make it a circle, which keeps the distance conservative for sphere tracing.
static float glassCoinSd(float3 p, GlassCoinGeometry g) {
    float w = max(g.rimWidth, 1e-3);
    float h = g.halfThickness;
    float2 q = float2(max(length(p.xy) - (g.radius - w), 0.0) * (h / w), p.z);
    return length(q) - h;
}

// coinNormal: the gradient of the ellipse (not of the scaled distance).
static float3 glassCoinNormal(float3 p, GlassCoinGeometry g) {
    float w = max(g.rimWidth, 1e-3);
    float h = max(g.halfThickness, 1e-3);
    float rl = length(p.xy);
    float2 radial = rl > 1e-5 ? p.xy / rl : float2(1.0, 0.0);
    float2 n = float2(max(rl - (g.radius - w), 0.0) / (w * w), p.z / (h * h));
    n = dot(n, n) > 1e-12 ? normalize(n) : float2(0.0, p.z >= 0.0 ? 1.0 : -1.0);
    return normalize(float3(radial * n.x, n.y));
}

// boundCylinder: ray vs. the bounding capped cylinder (radius R + margin, |z| <= h + margin).
static float2 glassCoinBound(float3 ro, float3 rd, GlassCoinGeometry g, float margin) {
    float Rb = g.radius + margin;
    float hb = g.halfThickness + margin;
    float tn = -1e9, tf = 1e9;
    if (abs(rd.z) < 1e-7) {
        if (abs(ro.z) > hb) {
            return float2(1e9, -1e9);
        }
    } else {
        float t1 = (-hb - ro.z) / rd.z;
        float t2 = (hb - ro.z) / rd.z;
        tn = max(tn, min(t1, t2));
        tf = min(tf, max(t1, t2));
    }
    float a = dot(rd.xy, rd.xy);
    float b = dot(ro.xy, rd.xy);
    float c = dot(ro.xy, ro.xy) - Rb * Rb;
    if (a < 1e-9) {
        if (c > 0.0) {
            return float2(1e9, -1e9);
        }
    } else {
        float disc = b * b - a * c;
        if (disc < 0.0) {
            return float2(1e9, -1e9);
        }
        float s = sqrt(disc);
        tn = max(tn, (-b - s) / a);
        tf = min(tf, (-b + s) / a);
    }
    return float2(tn, tf);
}

// traceOutside: (t, minDistance, hit). For misses t is the closest approach, used for silhouette AA.
static float3 glassCoinTraceOutside(float3 ro, float3 rd, GlassCoinGeometry g, float margin) {
    float2 span = glassCoinBound(ro, rd, g, margin);
    if (span.x > span.y || span.y < 0.0) {
        return float3(-1.0, 1e3, 0.0);
    }
    float t = max(span.x, 0.0);
    float3 p = ro + rd * t;
    if (abs(abs(p.z) - g.halfThickness) < 1e-3 && length(p.xy) <= g.radius - g.rimWidth) {
        return float3(t, 0.0, 1.0);
    }
    float minD = 1e3;
    float tMin = t;
    for (int i = 0; i < 64; i++) {
        float d = glassCoinSd(p, g);
        if (d < minD) {
            minD = d;
            tMin = t;
        }
        if (d < 0.001) {
            return float3(t, 0.0, 1.0);
        }
        t += max(d, 0.002);
        if (t > span.y + 0.01) {
            break;
        }
        p = ro + rd * t;
    }
    return float3(tMin, minD, 0.0);
}

// traceInside: distance to the far side of the glass from a point inside it.
static float glassCoinTraceInside(float3 ro, float3 rd, GlassCoinGeometry g) {
    float2 span = glassCoinBound(ro, rd, g, 0.0);
    float tExit = max(span.y, 0.0);
    float3 pe = ro + rd * tExit;
    if (length(pe.xy) <= g.radius - g.rimWidth + 1e-3) {
        return tExit;
    }
    float t = 0.0;
    float3 p = ro;
    for (int i = 0; i < 40; i++) {
        float d = -glassCoinSd(p, g);
        if (d < 0.0015) {
            return t;
        }
        t += max(d, 0.0015);
        p = ro + rd * t;
    }
    return t;
}

// rotationFor: R = Rx(pitch) · Ry(yaw), column-major.
static float3x3 glassCoinRotation(float yaw, float pitch) {
    float cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch);
    return float3x3(
        float3(cy, sp * sy, -cp * sy),
        float3(0.0, cp, sp),
        float3(sy, -sp * cy, cp * cy)
    );
}

// ------------------------------------------------------------------ environment

static float glassCoinSoftBox(float3 dir, float3 center, float2 halfSize, float softness) {
    float3 c = normalize(center);
    float3 up = abs(c.y) < 0.95 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
    float3 t = normalize(cross(up, c));
    float3 b = cross(c, t);
    float cosA = dot(dir, c);
    if (cosA <= 0.0) {
        return 0.0;
    }
    float2 uv = float2(dot(dir, t), dot(dir, b)) / cosA;
    float2 d = abs(uv) - halfSize;
    float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    return 1.0 - smoothstep(-softness, softness, dist);
}

static float3 glassCoinRotateY(float3 v, float a) {
    float c = cos(a), s = sin(a);
    return float3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

// A soft studio in front of the phone: the cover colours all around (only slightly brighter above, so every edge
// reads the same), a big key soft box up-left, a thin strip on each side (the quick glassy flash when it turns, the
// same either way) and a top bar. Glass reflects ~4 % head-on, so the face stays the photo; the lights glide across it
// when it tilts.
static float3 glassCoinEnvironment(float3 dir, constant GlassCoinUniforms &u) {
    dir = glassCoinRotateY(dir, u.light.x);
    float3 base = mix(u.envLow.rgb, u.envHigh.rgb, 0.4 + 0.2 * dir.y);
    float key = glassCoinSoftBox(dir, float3(-0.62, 0.48, 0.62), float2(0.62, 0.42), 0.18);
    float strip = glassCoinSoftBox(dir, float3(0.88, 0.05, 0.47), float2(0.05, 0.9), 0.05)
                + glassCoinSoftBox(dir, float3(-0.88, 0.05, 0.47), float2(0.05, 0.9), 0.05);
    float top = glassCoinSoftBox(dir, float3(0.05, 0.97, 0.25), float2(0.75, 0.07), 0.08);
    float3 warm = float3(1.0, 0.975, 0.93);
    float3 cool = float3(0.93, 0.97, 1.0);
    return base + u.optics.w * (warm * key * 3.8 + cool * strip * 3.4 + top * 2.0);
}

// ------------------------------------------------------------------ cover / shadow

// LiquidGlassShapes.metal: liquidGlassErf (Winitzki, |err| < 1.3e-4).
static float glassCoinErf(float x) {
    const float a = 0.147;
    float x2 = x * x;
    float t = 1.0 - exp(-x2 * (1.2732395 + a * x2) / (1.0 + a * x2));
    return sign(x) * sqrt(max(t, 0.0));
}

static float glassCoinBlurredCoverage(float distance, float sigma) {
    return 0.5 * (1.0 + glassCoinErf(distance / (sigma * 1.41421356)));
}

static float glassCoinEllipseDistance(float2 p, float2 axes) {
    float2 q = p / axes;
    float k = length(q);
    float g = length(q / axes);
    return g > 1e-5 ? k * (k - 1.0) / g : -min(axes.x, axes.y);
}

static float2 glassCoinShadowFrame(float2 p, float2 center, float angle) {
    float2 d = p - center;
    float c = cos(angle), s = sin(angle);
    return float2(c * d.x + s * d.y, -s * d.x + c * d.y);
}

// shadowAt: one soft shadow, centred under the glass (the light is the screen itself).
static float glassCoinShadow(float2 p, constant GlassCoinUniforms &u) {
    float strength = u.shadow1.z;
    if (strength <= 0.0) {
        return 0.0;
    }
    float d = glassCoinEllipseDistance(glassCoinShadowFrame(p, u.shadow0.xy, u.shadow1.x), u.shadow0.zw);
    return strength * glassCoinBlurredCoverage(-d, u.shadow1.y);
}

// glowAt: light of the glass colour hugging the avatar (the wide light of a colour change is drawn over the whole
// screen by GlassLightWaveNode; this stays well inside the layer).
static float3 glassCoinGlow(float2 p, constant GlassCoinUniforms &u) {
    float strength = u.light.w;
    if (strength <= 0.0) {
        return float3(0.0);
    }
    float rr = length(p) / (u.coin.y + 16.0);
    return u.glowColor.rgb * strength * exp(-rr * rr * 2.4);
}

static float3 glassCoinCoverAt(float2 p, constant GlassCoinUniforms &u, texture2d<half> cover, sampler s) {
    // coin-centred (y up) → layer points (y down) → cover uv
    float2 layerPoint = float2(u.frame1.z + p.x, u.frame1.w - p.y);
    float2 uv = (layerPoint - u.coverRect.xy) / u.coverRect.zw;
    float3 col = float3(cover.sample(s, clamp(uv, float2(0.001), float2(0.999))).rgb);
    col *= 1.0 - glassCoinShadow(p, u);
    col += glassCoinGlow(p, u);
    return col;
}

static float3 glassCoinCoverDispersed(float2 p0, float2 offset, constant GlassCoinUniforms &u, texture2d<half> cover, sampler s) {
    float k = u.optics.z;
    float r = glassCoinCoverAt(p0 + offset * (1.0 - k), u, cover, s).r;
    float g = glassCoinCoverAt(p0 + offset, u, cover, s).g;
    float b = glassCoinCoverAt(p0 + offset * (1.0 + k), u, cover, s).b;
    return float3(r, g, b);
}

// ------------------------------------------------------------------ card

static float3 glassCoinPhotoA(float2 local, constant GlassCoinUniforms &u, texture2d<half> photo, sampler s) {
    float2 uv = local / (2.0 * u.coin.y) + 0.5;
    uv.y = 1.0 - uv.y;
    return float3(photo.sample(s, uv, level(u.edge.y)).rgb);
}

// Side B is seen after a turn about the vertical axis: mirror x so it reads upright.
static float3 glassCoinPhotoB(float2 local, constant GlassCoinUniforms &u, texture2d<half> photo, sampler s) {
    float2 uv = float2(-local.x, local.y) / (2.0 * u.coin.y) + 0.5;
    uv.y = 1.0 - uv.y;
    return float3(photo.sample(s, uv, level(u.edge.y)).rgb);
}

// ------------------------------------------------------------------ coin sample

// shadeCoin: premultiplied colour of the glass avatar for one pose (alpha = coverage).
static float4 glassCoinShade(
    float2 p, float3x3 R, float3 eye, float3 dirW,
    constant GlassCoinUniforms &u,
    texture2d<half> photoA, texture2d<half> photoB, texture2d<half> cover,
    sampler photoSampler, sampler coverSampler
) {
    GlassCoinGeometry g;
    g.radius = u.coin.y;
    g.halfThickness = u.coin.z;
    g.rimWidth = u.edge.x;
    float glass = u.coin.w;
    float pxPerPt = u.frame1.y;
    float3 glassColor = u.glassColor.rgb;
    float glassTint = u.light.z;
    float edgeBoost = u.light.y;

    float3 coinCenter = float3(0.0, 0.0, u.coin.x);
    float3x3 toLocal = transpose(R);
    float3 ro = toLocal * (eye - coinCenter);
    float3 rd = toLocal * dirW;

    float aaMargin = 1.5 / pxPerPt;
    float3 hit = glassCoinTraceOutside(ro, rd, g, aaMargin);
    float coverage = 1.0;
    if (hit.z < 0.5) {
        coverage = saturate(0.5 - hit.y * pxPerPt);
        if (hit.x < 0.0 || coverage <= 0.0) {
            return float4(0.0);
        }
    }

    float3 P = ro + rd * hit.x;
    if (hit.z < 0.5) {
        P -= glassCoinNormal(P, g) * glassCoinSd(P, g);
    }
    float3 N = glassCoinNormal(P, g);
    float3 V = -rd;
    float cosI = saturate(dot(N, V));
    float F0 = 0.04;
    float fresnel = F0 + (1.0 - F0) * pow(1.0 - cosI, 5.0);

    float3 NW = R * N;
    float3 reflection = glassCoinEnvironment(reflect(dirW, NW), u);

    float ior = u.optics.y;
    float3 T1 = refract(rd, N, 1.0 / ior);
    float3 transmitted;
    float tCard = abs(T1.z) > 1e-6 ? -P.z / T1.z : -1.0;
    float3 Q = P + T1 * max(tCard, 0.0);
    if (tCard >= 0.0 && length(Q.xy) <= g.radius) {
        transmitted = (P.z >= 0.0) ? glassCoinPhotoA(Q.xy, u, photoA, photoSampler) : glassCoinPhotoB(Q.xy, u, photoB, photoSampler);
    } else {
        // Grazing rays that pass the photo: out through the far side, onto the cover.
        float tExit = glassCoinTraceInside(P + T1 * 0.002, T1, g);
        float3 E = P + T1 * (tExit + 0.002);
        float3 NE = glassCoinNormal(E, g);
        float3 T2 = refract(T1, -NE, ior);
        if (dot(T2, T2) < 1e-6) {
            T2 = reflect(T1, -NE);
        }
        float3 T2W = R * T2;
        float3 EW = R * E + coinCenter;
        float zBg = -2.0 * g.halfThickness - 1.0;
        float tb = abs(T2W.z) > 1e-5 ? (zBg - EW.z) / T2W.z : 1e3;
        float3 B = EW + T2W * max(tb, 0.0);
        float t0 = (zBg - eye.z) / dirW.z;
        float3 B0 = eye + dirW * t0;
        transmitted = T2W.z > 0.0 ? glassCoinEnvironment(T2W, u) * 0.6 : glassCoinCoverDispersed(B0.xy, B.xy - B0.xy, u, cover, coverSampler);
    }

    // 0 over the flat face → 1 at the silhouette.
    float band = smoothstep(g.radius - g.rimWidth, g.radius, length(P.xy));
    // Glass colour: a light wash over the photo, a little denser toward the edge (kept light: the colour is meant to
    // read as light, not as a rim), plus a little of its light.
    float tint = glassTint * (0.1 + 0.22 * band);
    transmitted = mix(transmitted, transmitted * mix(float3(1.0), glassColor, 0.85) * 1.12 + glassColor * 0.06, tint);
    // Matte haze in the band (LiquidGlass "matte": the edge reads on any photo).
    transmitted = mix(transmitted, transmitted + 0.09 * (1.0 - transmitted), band * glass);
    // The lens edge begins with a faint darker line (the light bending away there). The GLSL squares with
    // pow(x, 2.0); here x·x, because fast math computes pow(x, y) as exp2(y·log2(x)), NaN for x < 0.
    float lensOffset = (band - 0.16) / 0.12;
    float lensEdge = exp(-lensOffset * lensOffset);
    transmitted *= 1.0 - 0.08 * lensEdge * glass;

    float3 lit = mix(transmitted, reflection, saturate(fresnel * glass));

    // A faint overhead sheen (the glass buttons' inner sheen): a soft light above the phone seen in the face; it
    // slides across as the glass tilts.
    float sheen = smoothstep(0.1, 0.95, dot(reflect(dirW, NW), normalize(float3(-0.45, 0.75, 0.5))));
    lit += mix(float3(1.0), glassColor, 0.35 * glassTint) * (0.15 * sheen * glass);

    // Edge line: thin, bright where the surface turns away from the eye, the same all around with a faint crescent
    // up-left (no counter-light: every edge reads the same). Every pow() base here is >= 0 (fast math computes
    // pow(x, y) as exp2(y·log2(x)), NaN for x < 0).
    float edge = pow(1.0 - saturate(abs(dot(NW, -dirW))), 2.3);
    float2 n2 = normalize(NW.xy + float2(1e-5));
    float crescent = pow(max(dot(n2, normalize(float2(-0.62, 0.78))), 0.0), 2.0);
    float3 lineColor = mix(float3(1.0), mix(float3(1.0), glassColor, 0.5), glassTint);
    lit += lineColor * edge * (0.85 + 0.55 * crescent + edgeBoost) * glass;

    float2 flatXY = P.xy * min(1.0, (g.radius - 0.35) / max(length(P.xy), 1e-4));
    bool seesFront = hit.z > 0.5 ? (P.z >= 0.0 || rd.z < 0.0) : (rd.z < 0.0);
    if (g.halfThickness < 0.2) {
        seesFront = rd.z < 0.0;
    }
    float3 flatColor = seesFront ? glassCoinPhotoA(flatXY, u, photoA, photoSampler) : glassCoinPhotoB(flatXY, u, photoB, photoSampler);
    float3 color = mix(flatColor, lit, glass);
    color = color / (1.0 + max(color - 1.0, 0.0) * 0.6);
    return float4(color, 1.0) * coverage;
}

fragment half4 glassCoinFragment(
    GlassCoinVertexOut in [[stage_in]],
    constant GlassCoinUniforms &u [[ buffer(0) ]],
    texture2d<half> photoA [[ texture(0) ]],
    texture2d<half> photoB [[ texture(1) ]],
    texture2d<half> cover [[ texture(2) ]]
) {
    constexpr sampler photoSampler(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
    constexpr sampler coverSampler(coord::normalized, address::clamp_to_edge, filter::linear);

    // uv → layer pixels (allocation includes the edge inset) → layer points (y down) → coin-centred, y up.
    float2 allocationSize = u.frame0.zw + 2.0 * u.frame1.x;
    float2 pixel = in.uv * allocationSize - u.frame1.x;
    float pxPerPt = u.frame1.y;
    float2 layerPoint = pixel / pxPerPt;
    float2 p = float2(layerPoint.x - u.frame1.z, u.frame1.w - layerPoint.y);

    float3 eye = float3(0.0, 0.0, u.optics.x);
    float3 dirW = normalize(float3(p, 0.0) - eye);

    // Conservative bounds (pt): nothing at all farther than `influence`, no coin farther than `coinBound`.
    float r = length(p);
    if (r > u.edge.w) {
        return half4(0.0);
    }
    float4 coin = float4(0.0);
    if (r < u.edge.z) {
        int n = max(int(u.pose.w), 1);
        for (int i = 0; i < 8; i++) {
            if (i >= n) {
                break;
            }
            float f = n > 1 ? float(i) / float(n - 1) - 0.5 : 0.0;
            coin += glassCoinShade(p, glassCoinRotation(u.pose.x + u.pose.z * f, u.pose.y), eye, dirW, u, photoA, photoB, cover, photoSampler, coverSampler);
        }
        coin /= float(n);
    }

    // Around the glass, over the real cover: the shadow (black at alpha) and the glow (pure light: premultiplied rgb
    // with zero alpha adds).
    float4 under = float4(glassCoinGlow(p, u), glassCoinShadow(p, u));
    float4 result = coin + under * (1.0 - coin.a);
    return half4(result);
}
