// Glass avatar shader (WebGL2 / GLSL ES 3.0). The Metal port lives in
// ios/GlassCoinAvatar/Metal/GlassCoin.metal and mirrors this file function by function.
//
// Geometry: a two-sided photo card (radius R) inside a thin sheet of glass of the same
// radius. The sheet's faces are flat over the photo and its edge is a rounded band
// (an elliptical quarter-round, uRimWidth wide and 2·uHalfThickness thick) that lies
// INSIDE the photo's circle: the silhouette is exactly the avatar's, nothing frames it,
// and the glass only shows as a lens band along the edge (the photo folds into it), a
// thin bright edge line and the light gliding over the face when it tilts — the
// iOS 26 liquid-glass recipe of the designer video (1–2 pt edge, 4–6 pt denser band,
// faint crescent upper-left, minimal shadow). Units are points, origin at the centre,
// y up, z toward the viewer; the eye sits at z = eyeDistance (m34 = −1/d).
//
// Per pixel:
//   1. analytic slab/cylinder entry, sphere tracing of the rounded edge
//   2. Fresnel (Schlick) mix of a soft studio reflection and the refracted ray
//   3. refracted ray → photo card (A front, B back), or through the glass → the cover
//   4. glass colour (tint denser toward the edge), edge line, centred soft shadow, glow
//   5. motion blur: up to 8 yaw samples across the shutter for fast spins
// At glass = 0 the band and thickness collapse, shading fades out and the result is
// the flat avatar, pixel for pixel.

export const coinVertexShader = `#version 300 es
in vec2 aPosition;
void main() {
  gl_Position = vec4(aPosition, 0.0, 1.0);
}
`;

export const coinFragmentShader = `#version 300 es
precision highp float;
precision highp sampler2D;

out vec4 outColor;

uniform float uPxPerPt;
uniform vec2 uCenterPt;         // coin centre in canvas points (y up)
uniform vec2 uCanvasSizePt;
uniform float uYaw;             // rad, about the screen-vertical axis
uniform float uPitch;           // rad, about the screen-horizontal axis
uniform float uYawSpan;         // rad swept during the shutter (motion blur)
uniform int uSamples;           // 1…8
uniform float uCoinZ;           // local origin z in world
uniform float uRadius;          // photo = glass radius (pt)
uniform float uHalfThickness;   // h: half thickness of the sheet (pt)
uniform float uRimWidth;        // w: radial width of the rounded edge band (pt), w ≥ h
uniform float uGlass;           // 0 flat avatar … 1 full glass
uniform float uEyeDistance;
uniform float uIor;
uniform float uDispersion;

uniform sampler2D uPhotoA;
uniform sampler2D uPhotoB;
uniform float uPhotoLod;

uniform sampler2D uCover;
uniform vec4 uCoverRectPt;      // cover rect in canvas points: x, y (top, y-down), w, h

uniform vec3 uEnvLow;
uniform vec3 uEnvHigh;
uniform float uEnvRotation;     // device-motion parallax of the studio lights
uniform float uLightIntensity;

uniform vec3 uGlassColor;       // the glass colour the user picked
uniform float uGlassTint;       // 0 clear … 1 fully tinted
uniform float uEdgeBoost;       // extra edge light (colour change flash)

uniform vec2 uShadowCenter;     // pt, relative to coin centre (y up)
uniform vec2 uShadowAxes;
uniform float uShadowAngle;
uniform float uShadowSigma;
uniform float uShadowStrength;
uniform vec3 uGlowColor;
uniform float uGlow;
uniform float uCoinBound;       // pt: rays farther than this from the centre cannot hit the coin
uniform float uInfluence;       // pt: nothing at all is drawn farther than this

const float PI = 3.14159265;

// ------------------------------------------------------------------ geometry

// Flat faces at z = ±h over r < R − w; the edge is the ellipse ((r − (R − w))/w)² + (z/h)² = 1.
// The radial axis is scaled by h/w ≤ 1 to make it a circle, which keeps the distance
// conservative for sphere tracing.
float sdCoin(vec3 p) {
  float w = max(uRimWidth, 1e-3);
  float h = uHalfThickness;
  vec2 q = vec2(max(length(p.xy) - (uRadius - w), 0.0) * (h / w), p.z);
  return length(q) - h;
}

vec3 coinNormal(vec3 p) {
  float w = max(uRimWidth, 1e-3);
  float h = max(uHalfThickness, 1e-3);
  float rl = length(p.xy);
  vec2 radial = rl > 1e-5 ? p.xy / rl : vec2(1.0, 0.0);
  vec2 g = vec2(max(rl - (uRadius - w), 0.0) / (w * w), p.z / (h * h));
  g = dot(g, g) > 1e-12 ? normalize(g) : vec2(0.0, p.z >= 0.0 ? 1.0 : -1.0);
  return normalize(vec3(radial * g.x, g.y));
}

// Ray vs. the bounding capped cylinder (radius R + margin, |z| <= h + margin).
vec2 boundCylinder(vec3 ro, vec3 rd, float margin) {
  float Rb = uRadius + margin;
  float hb = uHalfThickness + margin;
  float tn = -1e9, tf = 1e9;
  if (abs(rd.z) < 1e-7) {
    if (abs(ro.z) > hb) return vec2(1e9, -1e9);
  } else {
    float t1 = (-hb - ro.z) / rd.z;
    float t2 = ( hb - ro.z) / rd.z;
    tn = max(tn, min(t1, t2));
    tf = min(tf, max(t1, t2));
  }
  float a = dot(rd.xy, rd.xy);
  float b = dot(ro.xy, rd.xy);
  float c = dot(ro.xy, ro.xy) - Rb * Rb;
  if (a < 1e-9) {
    if (c > 0.0) return vec2(1e9, -1e9);
  } else {
    float disc = b * b - a * c;
    if (disc < 0.0) return vec2(1e9, -1e9);
    float s = sqrt(disc);
    tn = max(tn, (-b - s) / a);
    tf = min(tf, (-b + s) / a);
  }
  return vec2(tn, tf);
}

// (t, minDistance, hit). For misses t is the closest approach (for silhouette AA).
vec3 traceOutside(vec3 ro, vec3 rd, float margin) {
  vec2 span = boundCylinder(ro, rd, margin);
  if (span.x > span.y || span.y < 0.0) return vec3(-1.0, 1e3, 0.0);
  float t = max(span.x, 0.0);
  vec3 p = ro + rd * t;
  if (abs(abs(p.z) - uHalfThickness) < 1e-3 && length(p.xy) <= uRadius - uRimWidth) return vec3(t, 0.0, 1.0);
  float minD = 1e3;
  float tMin = t;
  for (int i = 0; i < 64; i++) {
    float d = sdCoin(p);
    if (d < minD) { minD = d; tMin = t; }
    if (d < 0.001) return vec3(t, 0.0, 1.0);
    t += max(d, 0.002);
    if (t > span.y + 0.01) break;
    p = ro + rd * t;
  }
  return vec3(tMin, minD, 0.0);
}

float traceInside(vec3 ro, vec3 rd) {
  vec2 span = boundCylinder(ro, rd, 0.0);
  float tExit = max(span.y, 0.0);
  vec3 pe = ro + rd * tExit;
  if (length(pe.xy) <= uRadius - uRimWidth + 1e-3) return tExit;
  float t = 0.0;
  vec3 p = ro;
  for (int i = 0; i < 40; i++) {
    float d = -sdCoin(p);
    if (d < 0.0015) return t;
    t += max(d, 0.0015);
    p = ro + rd * t;
  }
  return t;
}

mat3 rotationFor(float yaw, float pitch) {
  float cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch);
  // R = Rx(pitch) · Ry(yaw); GLSL mat3 is column-major
  return mat3(
    cy,       sp * sy,  -cp * sy,
    0.0,      cp,        sp,
    sy,      -sp * cy,   cp * cy);
}

// ------------------------------------------------------------------ environment

float softBox(vec3 dir, vec3 center, vec2 halfSize, float softness) {
  vec3 c = normalize(center);
  vec3 up = abs(c.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
  vec3 t = normalize(cross(up, c));
  vec3 b = cross(c, t);
  float cosA = dot(dir, c);
  if (cosA <= 0.0) return 0.0;
  vec2 uv = vec2(dot(dir, t), dot(dir, b)) / cosA;
  vec2 d = abs(uv) - halfSize;
  float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
  return 1.0 - smoothstep(-softness, softness, dist);
}

vec3 rotateY(vec3 v, float a) {
  float c = cos(a), s = sin(a);
  return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

// A soft studio in front of the phone: the cover colours all around (only slightly
// brighter above, so every edge reads the same), a big key soft box up-left, a thin strip
// on each side (the quick glassy flash when it turns, the same either way) and a top bar.
// Glass reflects ~4 % head-on, so the face stays the photo; the lights glide across it
// when it tilts.
vec3 environment(vec3 dir) {
  dir = rotateY(dir, uEnvRotation);
  vec3 base = mix(uEnvLow, uEnvHigh, 0.4 + 0.2 * dir.y);
  float key = softBox(dir, vec3(-0.62, 0.48, 0.62), vec2(0.62, 0.42), 0.18);
  float strip = softBox(dir, vec3(0.88, 0.05, 0.47), vec2(0.05, 0.9), 0.05)
              + softBox(dir, vec3(-0.88, 0.05, 0.47), vec2(0.05, 0.9), 0.05);
  float top = softBox(dir, vec3(0.05, 0.97, 0.25), vec2(0.75, 0.07), 0.08);
  vec3 warm = vec3(1.0, 0.975, 0.93);
  vec3 cool = vec3(0.93, 0.97, 1.0);
  return base + uLightIntensity * (warm * key * 3.8 + cool * strip * 3.4 + top * 2.0);
}

// ------------------------------------------------------------------ cover / shadow

// Telegram LiquidGlassShapes.metal: liquidGlassErf (Winitzki, |err| < 1.3e-4)
float liquidGlassErf(float x) {
  const float a = 0.147;
  float x2 = x * x;
  float t = 1.0 - exp(-x2 * (1.2732395 + a * x2) / (1.0 + a * x2));
  return sign(x) * sqrt(max(t, 0.0));
}

float blurredCoverage(float distance, float sigma) {
  return 0.5 * (1.0 + liquidGlassErf(distance / (sigma * 1.41421356)));
}

float ellipseDistance(vec2 p, vec2 axes) {
  vec2 q = p / axes;
  float k = length(q);
  float g = length(q / axes);
  return g > 1e-5 ? k * (k - 1.0) / g : -min(axes.x, axes.y);
}

vec2 shadowFrame(vec2 p, vec2 center) {
  vec2 d = p - center;
  float c = cos(uShadowAngle), s = sin(uShadowAngle);
  return vec2(c * d.x + s * d.y, -s * d.x + c * d.y);
}

// One soft shadow, centred under the glass (the light is the screen itself).
float shadowAt(vec2 p) {
  if (uShadowStrength <= 0.0) return 0.0;
  float d = ellipseDistance(shadowFrame(p, uShadowCenter), uShadowAxes);
  return uShadowStrength * blurredCoverage(-d, uShadowSigma);
}

// Light of the glass colour hugging the avatar (the wide light of a colour change is
// drawn over the whole screen by the page; this stays well inside the canvas).
vec3 glowAt(vec2 p) {
  if (uGlow <= 0.0) return vec3(0.0);
  float rr = length(p) / (uRadius + 16.0);
  return uGlowColor * uGlow * exp(-rr * rr * 2.4);
}

vec3 coverAt(vec2 p) {
  vec2 canvasPt = uCenterPt + p;
  vec2 yDown = vec2(canvasPt.x, uCanvasSizePt.y - canvasPt.y);
  vec2 uv = (yDown - uCoverRectPt.xy) / uCoverRectPt.zw;
  vec3 col = texture(uCover, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
  col *= 1.0 - shadowAt(p);
  col += glowAt(p);
  return col;
}

vec3 coverDispersed(vec2 p0, vec2 offset) {
  float k = uDispersion;
  float r = coverAt(p0 + offset * (1.0 - k)).r;
  float g = coverAt(p0 + offset).g;
  float b = coverAt(p0 + offset * (1.0 + k)).b;
  return vec3(r, g, b);
}

// ------------------------------------------------------------------ card

vec3 photoA(vec2 local) {
  vec2 uv = local / (2.0 * uRadius) + 0.5;
  uv.y = 1.0 - uv.y;
  return textureLod(uPhotoA, uv, uPhotoLod).rgb;
}

// Side B is seen after a turn about the vertical axis: mirror x so it reads upright.
vec3 photoB(vec2 local) {
  vec2 uv = vec2(-local.x, local.y) / (2.0 * uRadius) + 0.5;
  uv.y = 1.0 - uv.y;
  return textureLod(uPhotoB, uv, uPhotoLod).rgb;
}

// ------------------------------------------------------------------ coin sample

// Premultiplied colour of the glass avatar for one pose (alpha = coverage).
vec4 shadeCoin(vec2 p, mat3 R, vec3 eye, vec3 dirW) {
  vec3 coinCenter = vec3(0.0, 0.0, uCoinZ);
  mat3 toLocal = transpose(R);
  vec3 ro = toLocal * (eye - coinCenter);
  vec3 rd = toLocal * dirW;

  float aaMargin = 1.5 / uPxPerPt;
  vec3 hit = traceOutside(ro, rd, aaMargin);
  float coverage = 1.0;
  if (hit.z < 0.5) {
    coverage = clamp(0.5 - hit.y * uPxPerPt, 0.0, 1.0);
    if (hit.x < 0.0 || coverage <= 0.0) return vec4(0.0);
  }

  vec3 P = ro + rd * hit.x;
  if (hit.z < 0.5) P -= coinNormal(P) * sdCoin(P);
  vec3 N = coinNormal(P);
  vec3 V = -rd;
  float cosI = clamp(dot(N, V), 0.0, 1.0);
  float F0 = 0.04;
  float fresnel = F0 + (1.0 - F0) * pow(1.0 - cosI, 5.0);

  vec3 NW = R * N;
  vec3 reflection = environment(reflect(dirW, NW));

  vec3 T1 = refract(rd, N, 1.0 / uIor);
  vec3 transmitted;
  float tCard = abs(T1.z) > 1e-6 ? -P.z / T1.z : -1.0;
  vec3 Q = P + T1 * max(tCard, 0.0);
  if (tCard >= 0.0 && length(Q.xy) <= uRadius) {
    transmitted = (P.z >= 0.0) ? photoA(Q.xy) : photoB(Q.xy);
  } else {
    // Grazing rays that pass the photo: out through the far side, onto the cover.
    float tExit = traceInside(P + T1 * 0.002, T1);
    vec3 E = P + T1 * (tExit + 0.002);
    vec3 NE = coinNormal(E);
    vec3 T2 = refract(T1, -NE, uIor);
    if (dot(T2, T2) < 1e-6) T2 = reflect(T1, -NE);
    vec3 T2W = R * T2;
    vec3 EW = R * E + coinCenter;
    float zBg = -2.0 * uHalfThickness - 1.0;
    float tb = abs(T2W.z) > 1e-5 ? (zBg - EW.z) / T2W.z : 1e3;
    vec3 B = EW + T2W * max(tb, 0.0);
    float t0 = (zBg - eye.z) / dirW.z;
    vec3 B0 = eye + dirW * t0;
    transmitted = T2W.z > 0.0 ? environment(T2W) * 0.6 : coverDispersed(B0.xy, B.xy - B0.xy);
  }

  // 0 over the flat face → 1 at the silhouette.
  float band = smoothstep(uRadius - uRimWidth, uRadius, length(P.xy));
  // Glass colour: a light wash over the photo, a little denser toward the edge (kept light:
  // the colour is meant to read as light, not as a rim), plus a little of its light.
  float tint = uGlassTint * (0.1 + 0.22 * band);
  transmitted = mix(transmitted, transmitted * mix(vec3(1.0), uGlassColor, 0.85) * 1.12 + uGlassColor * 0.06, tint);
  // Matte haze in the band (LiquidGlass "matte": the edge reads on any photo).
  transmitted = mix(transmitted, transmitted + 0.09 * (1.0 - transmitted), band * uGlass);
  // The lens edge begins with a faint darker line (the light bending away there).
  float lensEdge = exp(-pow((band - 0.16) / 0.12, 2.0));
  transmitted *= 1.0 - 0.08 * lensEdge * uGlass;

  vec3 lit = mix(transmitted, reflection, clamp(fresnel * uGlass, 0.0, 1.0));

  // A faint overhead sheen (the glass buttons' inner sheen): a soft light above the phone
  // seen in the face; it slides across as the glass tilts.
  float sheen = smoothstep(0.1, 0.95, dot(reflect(dirW, NW), normalize(vec3(-0.45, 0.75, 0.5))));
  lit += mix(vec3(1.0), uGlassColor, 0.35 * uGlassTint) * (0.15 * sheen * uGlass);

  // Edge line: thin, bright where the surface turns away from the eye, the same all
  // around with a faint crescent up-left (no counter-light: every edge reads the same).
  float edge = pow(1.0 - clamp(abs(dot(NW, -dirW)), 0.0, 1.0), 2.3);
  vec2 n2 = normalize(NW.xy + vec2(1e-5));
  float crescent = pow(max(dot(n2, normalize(vec2(-0.62, 0.78))), 0.0), 2.0);
  vec3 lineColor = mix(vec3(1.0), mix(vec3(1.0), uGlassColor, 0.5), uGlassTint);
  lit += lineColor * edge * (0.85 + 0.55 * crescent + uEdgeBoost) * uGlass;

  vec2 flatXY = P.xy * min(1.0, (uRadius - 0.35) / max(length(P.xy), 1e-4));
  bool seesFront = hit.z > 0.5 ? (P.z >= 0.0 || rd.z < 0.0) : (rd.z < 0.0);
  if (uHalfThickness < 0.2) seesFront = rd.z < 0.0;
  vec3 flatColor = seesFront ? photoA(flatXY) : photoB(flatXY);
  vec3 color = mix(flatColor, lit, uGlass);
  color = color / (1.0 + max(color - 1.0, 0.0) * 0.6);
  return vec4(color, 1.0) * coverage;
}

void main() {
  vec2 fragPt = gl_FragCoord.xy / uPxPerPt;
  vec2 p = fragPt - uCenterPt;
  vec3 eye = vec3(0.0, 0.0, uEyeDistance);
  vec3 dirW = normalize(vec3(p, 0.0) - eye);

  float r = length(p);
  if (r > uInfluence) {
    outColor = vec4(0.0);
    return;
  }
  vec4 coin = vec4(0.0);
  if (r < uCoinBound) {
    int n = max(uSamples, 1);
    for (int i = 0; i < 8; i++) {
      if (i >= n) break;
      float f = n > 1 ? float(i) / float(n - 1) - 0.5 : 0.0;
      coin += shadeCoin(p, rotationFor(uYaw + uYawSpan * f, uPitch), eye, dirW);
    }
    coin /= float(n);
  }

  // Around the glass, over the DOM cover: the shadow (black at alpha) and the glow
  // (pure light: rgb with zero alpha adds in premultiplied compositing).
  vec4 under = vec4(glowAt(p), shadowAt(p));
  outColor = coin + under * (1.0 - coin.a);
}
`;
