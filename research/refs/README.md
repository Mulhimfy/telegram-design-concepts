# Glass Coin avatar — research refs

Compiled 2026-10-12 for the @designers submission (web WebGL2 prototype + native Swift/Metal patch).
Files here:
- `README.md`: this file.
- [`designers-channel.md`](designers-channel.md): the latest 60 posts of t.me/s/designers (#266 → #198), with takeaways.
- `src/`: small reference sources, each with a URL and license header:
  - `liquid-glass-studio.fragment-main.glsl` (MIT)
  - `liquidGL.fragment.glsl.txt` (MIT)
  - `shuding.liquid-glass.js` (MIT)
  - `scrollmechanics.swift` (MIT)
  - `telegram.PremiumCoinComponent.swift` (GPL v2+). This file is not in the partial local checkout.

Local Telegram source paths below are relative to `/root/tgdesign/vendor/Telegram-iOS/` (commit f1dd7a2, 2026-10-07). GitHub links point to `master`.

---

## 0. What we should use (recommendations)

1. **Frame it as "the avatar lifts into Liquid Glass while touched".**
   - Apple: "Elements can even lift up into Liquid Glass temporarily, such as when you interact with a component" ([WWDC25-219 4:10](https://developer.apple.com/videos/play/wwdc2025/219/?time=250)).
   - Liquid Glass objects "materialize … by gradually modulating the light bending and lensing", not by fading ([2:55](https://developer.apple.com/videos/play/wwdc2025/219/?time=175)).
   - The HIG bans glass in the content layer, except for transient interactive elements like sliders and toggles ([HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials#Liquid-Glass)).
   - So: at rest the avatar stays a flat photo. On touch-down, ramp the IOR from 1.0 to 1.5 so it "materializes", and on settle ramp it back.
2. **Reuse Telegram's own 3D-coin interaction constants for in-house consistency.** Source: `PremiumCoinComponent` (§3.5).
   - Drag maps 1 pt to 1°.
   - Secondary axis is rubber-banded: range 60, c = 0.4.
   - Release with |angle| < 90° and |v| < 200 pt/s springs back. Otherwise it spins in the direction of the velocity. Above |v| > 600 pt/s it plays the "explode" flourish.
   - Spin spring: m = 1, k = 21, c = 5.8.
   - Tap tilts toward the tapped quadrant: ±0.6 rad yaw, ±0.3 rad pitch.
   - Generalize to any direction: rotate about the axis perpendicular to the drag vector.
3. **Choose the landing face with WWDC18 momentum projection, not raw position.** Use `landing = θ + (ω/1000)·d/(1−d)` with `d = 0.99` (UIScrollView `.fast`) and snap to the nearest k·π. Hand the release velocity over as the spring's initial velocity (§3.1, §3.3).
4. **Coin model: glass puck with a double-sided photo laminated at the mid-plane.**
   - Shape: rounded cylinder with R = avatar radius, half-thickness ≈ 0.08 R, edge radius ≈ 0.12–0.18 R. These ratios are our choice and need tuning.
   - The bevel gives Apple-style edge lensing: photo edges pulled inward, with the profile cover refracted through the rim.
   - Swap the hidden face's photo while the coin is edge-on, so each half-turn reveals the next photo (an endless coin).
5. **Optics.**
   - n = 1.5, so Schlick F0 = 0.04.
   - Handle total internal reflection: `refract()` returns 0, so fall back to `reflect()`.
   - Dispersion: one geometric trace plus a per-channel offset split (liquid-glass-studio style, ±2%), not three traces. Real BK7 Δn is only ≈ 0.011, so exaggerate (§2).
6. **Lighting.**
   - 2–3 procedural "studio strips" plus a top softbox in the reflection direction.
   - Rotate the rig with device gravity. Apple: lighting "responds to device motion" ([WWDC25-219 10:44](https://developer.apple.com/videos/play/wwdc2025/219/?time=644)).
   - Add a touch glow under the finger: glass "illuminates from within … starting right under your fingertips" ([12:05](https://developer.apple.com/videos/play/wwdc2025/219/?time=725)).
7. **Shadow.**
   - Analytic erf soft shadow of the projected ellipse. Telegram's Metal already ships this erf approximation (§2, "Soft contact shadow").
   - Make shadow opacity adaptive: stronger over text or busy content, weaker over light solids ([WWDC25-219 11:47](https://developer.apple.com/videos/play/wwdc2025/219/?time=707)).
   - Increase blur and offset with lift or toss height.
8. **Web prototype: WebGL2 only.**
   - Draw the profile cover yourself into a texture: gradient, pattern, gift backdrop.
   - Build a 2-pass separable blur, as in liquid-glass-studio.
   - Do **not** depend on the SVG `backdrop-filter: url(#…)` trick. It is Chromium-only ([kube.io](https://kube.io/blog/liquid-glass-css-svg/)), and the demo should run in iPhone Safari.
   - Use HTML/CSS for the chrome, with `-apple-system`.
9. **Native: follow the `LiquidGlassShapes` pattern.**
   - MetalEngine renders a displacement map into a sibling layer.
   - A `CABackdropLayer` uses the CAFilter `displacementMap` (inputAmount −32 pt, offset 0.5) for live refraction of what is behind.
   - A MetalEngine layer on top draws the photo face and speculars (§4.4).
   - Fall back to the non-refracting legacy look for: below iOS 26, Settings › Power Saving "interface effects", Reduce Transparency, and Reduce Motion. For Reduce Motion, crossfade the photos instead of spinning.
10. **Springs.**
    - Settle: use Telegram's iOS-26 house spring: m 1, k 555.027, c 47.118, which is ζ = 1.0 and response ≈ 0.267 s.
    - Overshoot only when the gesture carried momentum: WWDC18 uses 80% damping. WWDC23 says bounce 0.15–0.3 and to avoid going above 0.4 (§3.3).
11. **Haptics.**
    - Per-tick: `HapticFeedback().tap()` (selection generator) each time the coin passes edge-on. Rate-limit it, since the HIG says "avoid overusing haptics".
    - Landing: `impact(.soft/.light, intensity:)` scaled by landing speed.
    - Toss flourish: `impact(.medium)`, as on Telegram's coin.
    - Web: no programmable haptics on iOS Safari (§3.6).
12. **Gesture plumbing.**
    - Tilt immediately on touch-down.
    - Claim the pan after about 10 pt of hysteresis ([WWDC18-803 51:46](https://developer.apple.com/videos/play/wwdc2018/803/?time=3106)).
    - Opt the avatar out of Telegram's full-screen back swipe (`disablesInteractiveTransitionGestureRecognizer`).
    - Make sure the touch layer renders *something*; Telegram notes that empty layers get no touches (§4.4).
13. **Deliverable format.**
    - Code: native patch against Telegram-iOS (GPL v2+) plus a web demo link.
    - Video: square 1080×1080, about 1 min. The example attached to post #266 is 1:15, 1080×1080.
    - Record on a real iPhone.
14. **Fonts.** Ship no SF files. Use `font-family: -apple-system, system-ui, "Inter", sans-serif` and record on Apple hardware. Inter (OFL) is the fallback (§6).

---

## 1. Liquid Glass (iOS 26): official guidance and web re-implementations

### 1.1 Apple, primary sources

[WWDC25-219 "Meet Liquid Glass"](https://developer.apple.com/videos/play/wwdc2025/219/) (timestamps are from the transcript).

**Lensing**
- 1:55: "The primary way Liquid Glass visually defines itself is through … Lensing."
- 2:29: It "dynamically bends, shapes, and concentrates light in real time", whereas previous materials scattered light.

**Motion**
- 2:55: Objects materialize by modulating lensing.
- 3:38: Glass "responds to interaction by instantly flexing and energizing with light", with "gel-like flexibility".
- 4:10: Elements lift into glass on interaction.

**Adaptivity**
- 6:35: Shadows become more prominent as text scrolls under.
- 6:42: Tint and dynamic range shift to keep buttons legible.
- 6:51: Small elements flip between light and dark.
- 7:02: Larger glass "simulates a thicker … material": deeper shadows, "more pronounced lensing and refraction", softer scattering.
- 8:09: Light from nearby colorful content spills onto the surface and into the shadow.

**Layers**
- 10:44: A highlights layer, with "light sources … producing highlights that respond to geometry". The lights move during interactions, and "in some cases, the lighting responds to device motion".
- 11:47: Shadow opacity goes up over text and down over solid light backgrounds.
- 12:05: Glass illuminates from under the fingertip.

**Tint**
- 16:31: "Selecting a color generates a range of tones that are mapped to content brightness underneath", like real colored glass.

**Accessibility**
- 18:22: Reduce Transparency makes it frostier. Increase Contrast gives black/white with a border. Reduce Motion "disables any elastic properties".

[HIG › Materials › Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/materials#Liquid-Glass):
- Don't use it in the content layer, except for transient interactive controls (sliders, toggles) that "take on a Liquid Glass appearance … when a person activates it".
- Use it sparingly.
- Clear variant: only over rich media, with a **35% dark dimming layer** if the content underneath is bright.
- [HIG › Color › Liquid Glass color](https://developer.apple.com/design/human-interface-guidelines/color#Liquid-Glass-color): it has no inherent color and takes on content colors; apply color sparingly.

APIs, for reference only (Telegram renders its own glass):
- SwiftUI: `glassEffect(.regular.tint(…).interactive())` and `GlassEffectContainer` ([doc](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)).
- UIKit: `UIGlassEffect.isInteractive` ([doc](https://developer.apple.com/documentation/uikit/uiglasseffect)). Interactive glass "scales and bounces" ([WWDC25-284 23:03](https://developer.apple.com/videos/play/wwdc2025/284/?time=1383)), plus "shimmering" ([WWDC25-323 19:12](https://developer.apple.com/videos/play/wwdc2025/323/?time=1152)).

Newsroom: "Liquid Glass uses real-time rendering and dynamically reacts to movement with specular highlights" ([Apple, 2025-06-09](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)).

iOS 27 (WWDC26) adds a slider and settings to dial Liquid Glass up or down ([Tech Advisor, 2026-06-09](https://www.techadvisor.com/article/3160730/apples-liquid-glass-heading-in-a-bold-new-direction-to-an-off-switch.html)). The coin must look good at both ends.

### 1.2 How the web re-implementations compute refraction

**[kube.io — Liquid Glass in the Browser](https://kube.io/blog/liquid-glass-css-svg/)** (2025-09-04). Best explainer. An article only: the code is not released.
- Snell's law: `n1·sinθ1 = n2·sinθ2`, with n2 = 1.5.
- Surface height functions over the bezel, x ∈ [0, 1]:
  - convex circle: `√(1−(1−x)²)`
  - **convex squircle** (Apple-like, smooth flat-to-curve transition): `⁴√(1−(1−x)⁴)`
  - concave: `1 − convex`
  - lip: `mix(convex, concave, smootherstep(x))`
- Normal from the numeric derivative of the height.
- Displacement is symmetric around the bezel, so it pre-computes **127 samples** along one radius and rotates them.
- Normalizes by the maximum displacement.
- `feDisplacementMap`: R = x and G = y, encoded `128 + v·127`, with `scale` = maximum displacement in px.
- Specular: a rim light from the normal versus a fixed light angle (the demo uses −60°).
- Convex profiles keep rays inside the shape; concave ones push them outside.
- `backdrop-filter: url(#filter)` works in Chrome only.

**[iyinchao/liquid-glass-studio](https://github.com/iyinchao/liquid-glass-studio)** (MIT; WebGL2 and WebGPU). Copy in `src/`.
- Shapes: superellipse rounded-rect SDF, `smin` metaball merge.
- Pipeline: 4 passes — background, vertical blur, horizontal blur, composite.
- Edge refraction, with x = distance inside the edge divided by thickness:
  - `θi = asin((1−x)²)`
  - `θt = asin(sinθi/n)`
  - `edge = −tan(θt−θi)`
  - sample at `uv − normal·edge·refDistance`
- Dispersion: per-channel "IOR" of 0.98 / 1.00 / 1.02, scaling that offset.
- Fresnel and glare: glare angle from `atan2(normal)`, lightness boost in LCH.
- Spring-animated shapes.

**[naughtyduk/liquidGL](https://github.com/naughtyduk/liquidGL)** (MIT for code; `assets/` excluded).
- Backend chain: WebGPU → WebGL2 → WebGL1 → CSS.
- Snapshots the DOM with its own rasteriser.
- Shader:
  - `edge = 1 − smoothstep(0, bevelWidth·minSide, d)`
  - `offset = dir·(edge·refraction + edge¹⁰·bevelDepth)`
  - chroma: R sampled at `uv − offset·aberration`, B at `+`
  - tilt: `tan(tilt)·0.05`
  - "specular" is two drifting light blobs
- Defaults: `refraction 0.01, bevelDepth 0.08, bevelWidth 0.15, frost 0, specular true, magnify 1`.

**[rdev/liquid-glass-react](https://github.com/rdev/liquid-glass-react)** (MIT; SVG; displacement is invisible in Safari and Firefox).
- Defaults: `displacementScale 70, blurAmount 0.0625, saturation 140, aberrationIntensity 2, elasticity 0.15`.
- Chromatic aberration: 3 × `feDisplacementMap` with scale × (1, 1−0.05a, 1−0.1a), each channel isolated by `feColorMatrix`, then `screen` blended and masked to the edge.

**[shuding/liquid-glass](https://github.com/shuding/liquid-glass)** (MIT).
- Canvas-generated displacement: `uv·smoothstep(0, 1, smoothstep(0.8, 0, sdRoundRect − 0.15))`.
- CSS: `backdrop-filter: url(#f) blur(.25px) contrast(1.2) brightness(1.05) saturate(1.1)`.
- Shadow: `0 4px 8px rgba(0,0,0,.25), inset 0 -10px 25px rgba(0,0,0,.15)`.

**[Maxime Heckel — Refraction, dispersion, and other shader light effects](https://blog.maximeheckel.com/posts/refraction-dispersion-and-other-shader-light-effects/)**.
- `refract(eye, n, 1/ior)` per R/G/B channel.
- `LOOP` samples with growing `slide` to smooth the dispersion.
- Saturation boost.
- Fresnel `pow(1−|dot(eye,n)|, power)`.
- Blinn-Phong specular.
- Backside-then-frontside FBO pass for thick objects.

**Telegram's own** `submodules/TelegramUI/Components/LiquidGlassShapes` ([GitHub](https://github.com/TelegramMessenger/Telegram-iOS/tree/master/submodules/TelegramUI/Components/LiquidGlassShapes)), GPL v2+.
- Model: "a slab of glass with a rounded edge. Light entering the bevel bends towards the inside".
- `offset += inwardNormal · glassShift · falloff² · coverage`, where `falloff = 1 − sat(d/glassBand)`.
- Encoding: `rg = 0.5 − 0.5·offset/amount`, with `displacementAmount = 32` pt.
- Backdrop blur 1 pt, captured at 1× scale.

---

## 2. Rendering a thick glass coin in a shader

**Geometry ([IQ distfunctions](https://iquilezles.org/articles/distfunctions/))**
- `sdRoundedCylinder(p, ra, rb, h)`: `d = vec2(length(p.xz)−ra+rb, abs(p.y)−h+rb); return min(max(d.x,d.y),0)+length(max(d,0))−rb;`
- Swap y↔z so the coin axis is z.
- Bound the trace with IQ's analytic **capped-cylinder** intersector `cylIntersect(ro, rd, a, b, ra)`, which returns t and the normal ([IQ intersectors](https://iquilezles.org/articles/intersectors/), [shadertoy 4lcSRn](https://www.shadertoy.com/view/4lcSRn)). Then sphere-trace the SDF; it is convex, so ~10–20 steps.
- Normals: [IQ tetrahedron technique](https://iquilezles.org/articles/normalsSDF/), 4 taps: `normalize(k.xyy·f(p+k.xyy·h)+k.yyx·f(p+k.yyx·h)+k.yxy·f(p+k.yxy·h)+k.xxx·f(p+k.xxx·h))`.

**Optics**
- GLSL `refract` computes `k = 1 − η²(1 − (N·I)²)` and returns **0 when k < 0**, which is total internal reflection ([docs.gl/refract](https://docs.gl/sl4/refract)). Glass→air critical angle is asin(1/1.5) ≈ 41.8°.
- Fresnel, [Schlick](https://en.wikipedia.org/wiki/Schlick%27s_approximation): `R = R0 + (1−R0)(1−cosθ)⁵`, `R0 = ((n1−n2)/(n1+n2))²`, which is 0.04 for 1.5.
- Dispersion, [Cauchy](https://en.wikipedia.org/wiki/Cauchy%27s_equation): `n(λ) = A + B/λ²`. For BK7, A = 1.5046 and B = 0.00420 µm², giving n ≈ 1.5145 (650 nm) / 1.5185 (550 nm) / 1.5253 (450 nm). This is too subtle for UI, so exaggerate 2–4× or use liquid-glass-studio's ±2% offset split.

**Lighting (cheap UI environment)**
- Procedural softboxes and strips evaluated in the reflected direction (snippet below).
- Reference studio layout: three.js [`RoomEnvironment`](https://github.com/mrdoob/three.js/blob/dev/examples/jsm/environments/RoomEnvironment.js) (MIT): 6 emissive boxes plus a key light. Mimic their placement analytically.
- Rig thinking (key sun, sky fill, bounce light, each tuned separately): [IQ outdoors lighting](https://iquilezles.org/articles/outdoorslighting/).

**Soft contact shadow**
- [Evan Wallace, fast rounded-rectangle shadows](https://madebyevan.com/shaders/fast-rounded-rectangle-shadows/) (CC0): the Gaussian integral is `½(1+erf(x/(σ√2)))`, and a blurred box is the product of two such 1D terms. Rounded corners need a few samples along the second axis.
- Telegram uses the same erf trick (Winitzki approximation, a = 0.147) in `LiquidGlassShapes.metal`, `liquidGlassBlurredCoverage`.
- For a tilted disc, use an ellipse with axes (R, R·|n_z|) rotated to the tilt axis. Exact distance: [IQ ellipse distance](https://iquilezles.org/articles/ellipsedist/). For a soft shadow the cheap `(|q/ab|−1)·min(a,b)` is enough.

**Coin shader sketch** (WebGL2, untested; units are device px; the cover plane is z = 0 and the coin floats at `uC.z`):

```glsl
float sdCoin(vec3 p){ vec2 d=vec2(length(p.xy)-uR+uE, abs(p.z)-uH+uE);               // IQ rounded cylinder (axis z)
  return min(max(d.x,d.y),0.)+length(max(d,0.))-uE; }
vec3 nrm(vec3 p){ const vec2 k=vec2(1,-1); float e=1e-3*uR;                            // IQ tetrahedron normal
  return normalize(k.xyy*sdCoin(p+k.xyy*e)+k.yyx*sdCoin(p+k.yyx*e)+k.yxy*sdCoin(p+k.yxy*e)+k.xxx*sdCoin(p+k.xxx*e)); }
float trace(vec3 ro, vec3 rd, float s, float t){                                        // s=+1 outside, -1 inside; t=start
  for(int i=0;i<48;i++){ float d=s*sdCoin(ro+rd*t); if(d<1e-3*uR) return t; t+=max(d,2e-3*uR); if(t>12.*uR) break; } return -1.; }
vec3 cover(vec3 pw, vec3 dw, float blur){ float s=-pw.z/min(dw.z,-1e-3); vec2 uv=(pw.xy+dw.xy*s)/uRes;
  return mix(texture(uBg,uv).rgb, texture(uBgBlur,uv).rgb, blur); }
vec3 studio(vec3 r){ float key=smoothstep(.55,.95,dot(r,uL));                           // uL rotated by device gravity
  float strip=smoothstep(.10,0.,abs(r.x+.6))*smoothstep(-.2,.5,r.y); return vec3(1.6*key+.7*strip); }
void main(){
  vec3 cam=vec3(uC.xy, uC.z+8.*uR), rdw=normalize(vec3(gl_FragCoord.xy,0.)-cam);        // 1:1 on the cover plane
  vec3 ro=transpose(uRot)*(cam-uC), rd=transpose(uRot)*rdw; vec3 base=cover(cam,rdw,0.);
  float t=trace(ro,rd,1.,0.); if(t<0.){ o=vec4(base,1.); return; }                       // (bound with cylIntersect first)
  vec3 p=ro+rd*t, n=nrm(p); float ior=mix(1.,1.5,uGlass);                              // uGlass: "materialize" lensing
  float F=.04+.96*pow(1.-clamp(dot(-rd,n),0.,1.),5.);                                     // Schlick
  vec3 t1=refract(rd,n,1./ior); float s=trace(p,t1,-1.,.02*uR); float zc=-p.z/t1.z; vec3 body; // start inside, skip entry face
  if(zc>0. && (s<0.||zc<s) && length((p+t1*zc).xy)<uR){                                  // laminated 2-sided photo at z=0
    vec2 q=(p+t1*zc).xy/(2.*uR)+.5; body = t1.z<0. ? texture(uPhotoA,q).rgb : texture(uPhotoB,vec2(1.-q.x,q.y)).rgb;
  } else {                                                                                 // rim: refract the cover
    vec3 p2=p+t1*max(s,0.), n2=nrm(p2), t2=refract(t1,-n2,ior); if(dot(t2,t2)==0.) t2=reflect(t1,-n2); // TIR → bounce
    vec3 pw=uRot*p2+uC, dw=uRot*t2; vec3 off=vec3((dw.xy-rdw.xy)*uR*.02,0.);             // cheap dispersion split
    body=vec3(cover(pw+off,dw,.3).r, cover(pw,dw,.3).g, cover(pw-off,dw,.3).b);
  }
  o=vec4(mix(body, studio(uRot*reflect(rd,n)), F), 1.);
}
float erfW(float x){ float a=.147,x2=x*x; return sign(x)*sqrt(max(0.,1.-exp(-x2*(1.2732395+a*x2)/(1.+a*x2)))); }
float coinShadow(vec2 p, vec2 c, vec2 ab, float ang, float sigma){                        // add to `base`, alpha-adaptive
  vec2 q=mat2(cos(ang),-sin(ang),sin(ang),cos(ang))*(p-c); float d=(length(q/ab)-1.)*min(ab.x,ab.y);
  return .5*(1.-erfW(d/(sigma*1.41421356))); }
```

---

## 3. Fluid-interface physics, springs, haptics

### 3.1 WWDC18-803 "Designing Fluid Interfaces"

[Session](https://developer.apple.com/videos/play/wwdc2018/803/), with code in [nathangitter/fluid-interfaces](https://github.com/nathangitter/fluid-interfaces) (Apache-2.0).

- **Momentum projection** (45:01–47:37): `func project(initialVelocity v: CGFloat, decelerationRate d: CGFloat) -> CGFloat { (v/1000) * d / (1 - d) }`. Pick the endpoint nearest the *projected* position. It "isn't just useful for positions … scales, or even for rotations".
- Deceleration rates per ms: `.normal` = 0.998 and `.fast` = 0.99 ([React Native ScrollView docs](https://reactnative.dev/docs/scrollview)).
- Exact decay ([ScrollMechanics](https://github.com/super-ultra/ScrollMechanics), MIT):
  - `x(t) = x0 + v0·(d^(1000t) − 1)/(1000·ln d)`
  - `x(∞) = x0 − v0/(1000·ln d)`
  - `v(t) = v0·d^(1000t)`
- Rubber-banding (17:01): soft boundaries, never a hard wall. Hand-offs between tracked objects should be smooth curves.
- Springs (34:14–35:14): designers tune **damping ratio + response**; mass, stiffness and damping stay behind the scenes.
  - Start from **100% damping** (36:21).
  - "If the gesture … has momentum, … reward that momentum with a little bit of overshoot". Music Now Playing uses **80% damping** on swipe-dismiss (36:39–37:10).
- Gestures:
  - Hysteresis is "usually 10 points" (51:46).
  - Keep the touch's relative offset and never snap to the center (52:22).
  - Compute velocity from the touch history (52:34).
  - Prefer continuous recognizers over `UISwipeGestureRecognizer` (54:22).
  - Motion stretching (20:02).
  - "Behavior rather than animation" (20:42).

### 3.2 Rubber band
- `f(x) = (1 − 1/(x·c/d + 1))·d`, which equals `x·d·c/(d + c·x)`. UIScrollView uses **c = 0.55**; d = view dimension.
  - Code: [ScrollMechanics `RubberBand.swift`](https://github.com/super-ultra/ScrollMechanics/blob/master/ScrollMechanics/Sources/RubberBand.swift).
  - Origin: [Grant Paul's tweet](https://twitter.com/chpwn/status/285540192096497664), via [this write-up](https://teletype.in/@swift-discipline/how-uiscrollview-works).
- Telegram's variant is `scrollingRubberBandingOffset(offset:bandingStart:range:coefficient: 0.4)` in `submodules/Display/Source/ListViewAnimation.swift:232`. The coin uses range 60 and c 0.4.

### 3.3 Spring parameter conversions (mass m)
- From response/duration T and damping ratio ζ: `k = m·(2π/T)²` and `c = 4π·ζ·m/T`. This is [fluid-interfaces `Spring.swift`](https://github.com/nathangitter/fluid-interfaces/blob/master/FluidInterfaces/FluidInterfaces/Spring.swift) and [Wave](https://github.com/jtrivedi/Wave) (MIT).
  - Back the other way: `T = 2π/√(k/m)`, `ζ = c/(2√(k·m))`.
- [WWDC23-10158 "Animate with springs"](https://developer.apple.com/videos/play/wwdc2023/10158/) at 19:26 gives `mass = 1`, `stiffness = (2π ÷ duration)²`, `damping = (1 − bounce)·4π ÷ duration` for bounce ≥ 0. So **ζ = 1 − bounce**, and for bounce < 0, ζ = 1/(1 + bounce). The page's plain-text slide drops the parentheses; this is the physically consistent reading.
- Bounce guidance (18:56+): 0 is smooth, ~0.15 is brisk, ~0.3 is noticeably bouncy, and be cautious above ~0.4.
- Velocity continuity (5:32): only springs preserve gesture velocity.
- SwiftUI:
  - `spring(response: 0.5, dampingFraction: 0.825)` and `interactiveSpring(response: 0.15, dampingFraction: 0.86, blendDuration: 0.25)` are the defaults ([doc](https://developer.apple.com/documentation/swiftui/animation/spring%28response:dampingfraction:blendduration:%29), [doc](https://developer.apple.com/documentation/swiftui/animation/interactivespring%28response:dampingfraction:blendduration:%29)).
  - `spring(duration: 0.5, bounce: 0)`, where duration is perceptual and ≈ the settling duration ([doc](https://developer.apple.com/documentation/swiftui/spring/init%28duration:bounce:%29)).
  - `Spring.settlingDuration` uses ε = 0.001 ([doc](https://developer.apple.com/documentation/swiftui/spring/settlingduration)).
- UIKit:
  - `UISpringTimingParameters.initialVelocity` is **normalized to distance**: `dx = vx/(x_target − x_current)`, and 0 if the distance is 0 ([doc](https://developer.apple.com/documentation/uikit/uispringtimingparameters/initialvelocity)).
  - `CASpringAnimation.settlingDuration` "may not [be] the same as duration". Telegram usually sets `duration = settlingDuration` ([doc](https://developer.apple.com/documentation/quartzcore/caspringanimation/settlingduration)).
  - Since iOS 17: `CASpringAnimation(perceptualDuration:bounce:)` and `UISpringTimingParameters(duration:bounce:initialVelocity:)`.
- Analytic solution, for evaluating a spring per frame in Metal uniforms. Under-damped: `x(t) = e^(−βt)(c1·cos ω′t + c2·sin ω′t)`, with β = c/2m, ω′ = √(ω0² − β²), c1 = x0, c2 = (v0 + βx0)/ω′. Critically damped: `e^(−βt)(c1 + c2·t)`. Source: [ScrollMechanics `SpringTimingParameters.swift`](https://github.com/super-ultra/ScrollMechanics/blob/master/ScrollMechanics/Sources/SpringTimingParameters.swift).
  - Or a semi-implicit Euler step: `v += (−k(x−x*) − c·v)/m·dt; x += v·dt`, as in Wave.
  - Wave presets: interactive ζ 0.8 / response 0.20; animated ζ 1.0 / response 0.82.

### 3.4 Telegram house springs (local source)

| Where | m | k | c | Derived | Use |
|---|---|---|---|---|---|
| `makeSpringAnimationImpl`, pre-iOS 26 (`UIKitRuntimeUtils/…/UIKitUtils.m`) | 3 | 1000 | 500 | ζ ≈ 4.6, overdamped, 0.5 s | `.spring` curve |
| `make26SpringAnimationImpl`, iOS 26 | 1 | 555.027 | 47.118 | **ζ = 1.00, response ≈ 0.267 s** | `.spring` on iOS 26 |
| `.customSpring` defaults (`Display/Source/ContainedViewLayoutTransition.swift:49`) | 5 | 900 | caller | response ≈ 0.468 s | custom bounce |
| `PremiumCoinComponent` spin and tap | 1 | 21 | 5.8 | ζ ≈ 0.63, response ≈ 1.37 s | 3D coin; `duration = settlingDuration·0.75` |

### 3.5 Interaction precedents

**Telegram's draggable 3D coin and star** ([`PremiumCoinComponent.swift`](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/TelegramUI/Components/Premium/PremiumCoinComponent/Sources/PremiumCoinComponent.swift), copy in `src/`; `PremiumStarComponent` is a sibling). SceneKit node `eulerAngles`.
- Pan:
  - yaw = `deg2rad(translation.x)`
  - pitch = rubber-banded `translation.y` (range 60, c 0.4)
- Release: `smallAngle = |yaw| < π/2 && |vx| < 200` springs back to 0. Otherwise it springs to ±2π, signed by vx. `explode` (particles) fires if `|vx| > 600`.
  - Spring `initialVelocity = |vx / distanceDeg|`.
- Tap: 0.25 s easeOut tilt to (±0.3 pitch, ±0.6 yaw), then spring back, with `hapticFeedback.tap()`. A second tap while that tilt is still animating plays a full mirrored spin with explode and `impact(.medium)`.

**Telegram avatar ↔ Dynamic Island**
- Local code: `PeerInfoScreen/Sources/DynamicIslandBlurNode.swift`, `PeerInfoAvatarTransformContainerNode.swift`, `PeerInfoAvatarListNode.swift`.
- Metaball write-up: [Habr](https://habr.com/en/articles/1004752), Flutter, field `Σ r²/|p−c|²`, threshold 1.0, edge 0.04. Code: [flutter_metaballs](https://github.com/DmitriiProshutinskii/flutter_metaballs), no license, so reference only.

**Apple Wallet's Apple Pay Cash card** (iOS 12) "shimmers like a holographic material as you move the phone around". The effect is anisotropic, not environment-lit ([Daring Fireball](https://daringfireball.net/linked/2019/01/10/)).
- Rebuilds: [jtrivedi/Apple-Cash-Animation](https://github.com/jtrivedi/Apple-Cash-Animation) (MIT) and [efremidze/Shiny](https://github.com/efremidze/Shiny) (MIT, gyroscope-driven iridescence). Use these for motion-driven specular.

**Liquid Glass system controls**: slider and toggle thumbs become glass only while active ([HIG](https://developer.apple.com/design/human-interface-guidelines/materials#Liquid-Glass)). This is the closest system precedent for "lift into glass on touch".

Optional settle flourish: [Euler's disk](https://en.wikipedia.org/wiki/Euler%27s_Disk). A spinning disc settles with *accelerating* wobble frequency, so haptic ticks could speed up while intensity falls.

### 3.6 Haptics

[HIG › Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics):
- Use system patterns per their meaning.
- Impact **light/medium/heavy** describe UI object *mass*; **rigid/soft** describe hardness. **Selection** is for "values … changing".
- "Avoid overusing haptics".
- "Match the intensity and sharpness of a haptic with … the animation it accompanies".
- Make haptics optional.
- Core Haptics: transient vs. continuous events, each with sharpness and intensity.

API:
- `UIImpactFeedbackGenerator.impactOccurred(intensity: 0…1)` ([doc](https://developer.apple.com/documentation/uikit/uiimpactfeedbackgenerator/impactoccurred%28intensity:%29)), plus `impactOccurred(at:)`.
- `UISelectionFeedbackGenerator.selectionChanged(at:)` ([doc](https://developer.apple.com/documentation/uikit/uiselectionfeedbackgenerator)).
- Call `prepare()` when the gesture begins ([doc example](https://developer.apple.com/documentation/uikit/uiimpactfeedbackgenerator)).

Telegram wrapper `Display/Source/HapticFeedback.swift`:
- `tap()` → selection generator.
- `impact(.light/.medium/.heavy/.soft/.rigid, intensity:)`.
- `.click05` → intensity 0.3, `.click06` → 0.4, `.veryLight` → 0.3.
- `prepareTap()` / `prepareImpact()`.

Web:
- iOS Safari has **no Vibration API** ([caniuse data](https://github.com/Fyrd/caniuse/blob/main/features-json/vibration.json), `ios_saf: n` through 27.2).
- [tijnjh/ios-haptics](https://github.com/tijnjh/ios-haptics) (MIT) toggles a hidden `<input type=checkbox switch>` behind a label on a real tap, so it cannot be driven per frame during a spin. Use visual ticks on web.
- Device tilt: `DeviceOrientationEvent.requestPermission()` needs a user gesture on Safari ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/DeviceOrientationEvent/requestPermission_static)).

### 3.7 Web gesture → coin sketch (JS, untested)

```js
const DEG = Math.PI / 180;                                                   // Telegram coin: 1 pt of drag = 1°
const rubber = (x, dim, c = 0.55) => Math.sign(x) * (1 - 1 / (Math.abs(x) * c / dim + 1)) * dim; // UIScrollView
const project = (v, d = 0.99) => (v / 1000) * d / (1 - d);                  // WWDC18 (.fast 0.99, .normal 0.998)
const spring = (T, zeta, m = 1) => ({ m, k: m * (2 * Math.PI / T) ** 2, c: 4 * Math.PI * zeta * m / T });
function step(s, target, dt, { m, k, c }) {                                  // semi-implicit Euler (Wave)
  const a = (-k * (s.x - target) - c * s.v) / m; s.v += a * dt; s.x += s.v * dt;
}
// pointerdown: setPointerCapture, glass 0→1 (IOR ramp), prepare tilt toward touch point.
// pointermove: d = total translation (pt). axis = normalize(-d.y, d.x) in screen plane; angle = |d|·DEG.
//   Keep ~80 ms of samples for release velocity (WWDC18: use touch history, not the last delta).
// pointerup: v = |velocity| (pt/s) along d; omega = v·DEG; landing = angle + project(omega);
//   Telegram thresholds: angle < 90° && v < 200 → target 0; else target = round(landing/π)·π (≥ 1 half-turn);
//   v > 600 → toss flourish (lift z, bigger/blurrier shadow).
//   Spring: momentum → spring(0.55, 0.8) (WWDC18 "80% damping"), otherwise spring(0.4, 1.0); s = {x: angle, v: omega}.
//   Each time x crosses π/2 + kπ (edge-on): swap the hidden face's photo, emit a visual "tick" (native: HapticFeedback.tap()).
```

---

## 4. Telegram context, 2025–2026

### 4.1 Liquid Glass in Telegram iOS (official blog)
- 2025-10-10: "Liquid Glass for iOS 26". The bottom navigation bar, keyboard and sticker panel gained "transparent elements with a satisfying refraction effect as you scroll" ([blog](https://telegram.org/blog/comments-in-video-chats-threads-for-bots)).
- 2025-11-19: "even more Liquid Glass interfaces, like **redesigned profiles**, an updated Settings menu and a new attachment menu" ([blog](https://telegram.org/blog/live-stories-gift-auctions)).
- 2026-01-03: "fully supports Liquid Glass … throughout the entire app". Interface effects can be reduced in **Settings › Power Saving** ([blog](https://telegram.org/blog/new-design-ai-summaries)).
- 2026-02-09: redesigned media viewer, sticker and emoji pack previews, and "updated context menus in user profiles" ([blog](https://telegram.org/blog/crafting-android-design-and-more)).
- The repo builds against the **iOS 27 SDK**. Its [CLAUDE.md](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/CLAUDE.md) (81 KB, house rules for AI-assisted work) and `docs/` are worth reading before writing the native patch, especially:
  - [context-menu-liquid-morph.md](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/docs/context-menu-liquid-morph.md): profile header glass capsules; frame-rate range 48–120 Hz.
  - [ios27-windows-and-touches.md](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/docs/ios27-windows-and-touches.md): "A layer that renders nothing receives no real touches".
  - Rules: a view never sets its own `frame`; per-pixel Swift is slow in `-Onone` modules.

### 4.2 Profile features to stay compatible with
- **Wear a collectible gift**: profile appearance matches the gift's **backdrop and symbol** (2025-01-24, [blog](https://telegram.org/blog/wear-gifts-blockchain-and-more)).
- **Pin up to 6 gifts** on the profile cover (2025-03-07, [blog](https://telegram.org/blog/star-messages-gateway-2-0-and-more)). They are laid out around the avatar in `PeerInfoCoverComponent/Sources/PeerInfoGiftsCoverComponent.swift` (polar positions around `avatarCenter`, `StarsEffectLayer`).
- **Music on profile**: "the track appears in a stylish bar beneath your photo". Also a default profile tab and gift themes (2025-08-31, [blog](https://telegram.org/blog/profile-music-gift-themes)). Bot API: `getUserProfileAudios`.
- **Profile color settings**: "select a gift to use its backdrop and symbol on your profile cover" (2025-10-10, [blog](https://telegram.org/blog/comments-in-video-chats-threads-for-bots)).
- Other gift features: collections (2025-07-31), purchase offers (2025-12-12), crafting (2026-02-09), signed gifts (2026-08-25) ([blog index](https://telegram.org/blog)).
- Colors for the cover in the web replica:
  - Bot API `UniqueGiftBackdropColors {center_color, edge_color, symbol_color, text_color}`: radial gradient center→edge, with the symbol pattern tinted by `symbol_color`.
  - `UniqueGiftColors` (light/dark main + 1–3 other colors).
  - The 16 [profile accent colors](https://core.telegram.org/bots/api#profile-accent-colors) (light/dark).
  - All in the [Bot API docs](https://core.telegram.org/bots/api).
- Collectible basics: "background color, icon and number" traits, 1400+ appearances at launch ([blog](https://telegram.org/blog/collectible-gifts-and-more)).

### 4.3 @designers submission rules
- [Post #266](https://t.me/designers/266), 2026-10-11:
  - Accepted: "**Working, ready-to-implement code** complemented by **a demo video** of your feature in action".
  - No longer accepted: static mockups, code-less demo videos, text-only concepts.
  - Submit via a direct message to the channel: `t.me/designers?direct` ([Direct Messages for Channels](https://telegram.org/blog/direct-to-channel-trim-voice-and-more)).
  - The attached example by their iOS designer is 1:15, 1080×1080.
- Recent contest context, all forwarded from [@contest](https://t.me/s/contest):
  - [Design Contest 2026 R2](https://t.me/contest/451): Before/After improvements to *existing* features, max 2.
  - Earlier rounds wanted iOS and Android, day and night, mp4 without sound, and Lottie/TGS for animated icons ([#251](https://t.me/designers/251)).
- Full dump: [designers-channel.md](designers-channel.md).

### 4.4 Telegram-iOS code anchors

All under `submodules/` (GPL v2 or later, per [telegram.org/apps](https://telegram.org/apps#source-code)).

- **Profile header**: `TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/`
  - `PeerInfoHeaderNode.swift` (2.9k lines)
  - `PeerInfoAvatarListNode.swift`
  - `PeerInfoAvatarTransformContainerNode.swift`
  - `DynamicIslandBlurNode.swift`
  - `PeerInfoHeaderNavigationButtonContainerNode.swift` (glass nav capsules)
  - `PeerInfoCoverComponent` (pattern) and `PeerInfoGiftsCoverComponent`
- **Glass**:
  - `TelegramUI/Components/LiquidGlassShapes/{Metal/LiquidGlassShapes.metal, Sources/LiquidGlassShapesLayer.swift, Sources/LiquidGlassBackdropLayers.swift}`
  - `GlassBackgroundComponent` (`createBackdropLayer()` in `LegacyGlassView.swift`)
  - `SpaceWarpView` (the original displacement-map trick)
  - `Display/Source/UIKitUtils.swift:911` `CALayer.displacementMap()` → `CAFilter "displacementMap"`
- **Rendering**: `MetalEngine/Sources/MetalEngine.swift`. `MetalEngineSubjectLayer` plus `MetalEngineSubject` with `context.renderToLayer(…)`; see `LiquidGlassShapesLayer` as the worked example.
- **Gestures**: `Display/Source/InteractiveTransitionGestureRecognizer.swift`. Use `view.disablesInteractiveTransitionGestureRecognizer = true` or `interactiveTransitionGestureRecognizerTest` to keep the full-screen back swipe off the avatar. For UIKit containers on iOS 26, set failure requirements on `interactiveContentPopGestureRecognizer` ([WWDC25-284 13:21](https://developer.apple.com/videos/play/wwdc2025/284/?time=801)).

```swift
// Backdrop refraction, the LiquidGlassBackdropLayers pattern (iOS 26+; private CAFilter, as Telegram already does)
guard let filter = CALayer.displacementMap(), let backdrop = createBackdropLayer() else { /* legacy look */ return }
mapLayer.name = "coinDisplacementMap"                       // MetalEngineSubjectLayer; RG = 0.5 - 0.5*offset/32
filter.setValue(mapLayer.name, forKey: "inputSourceSublayerName")
filter.setValue(-32.0 as NSNumber, forKey: "inputAmount")   // LiquidGlassShapesConstants.displacementAmount
filter.setValue(NSValue(cgPoint: CGPoint(x: 0.5, y: 0.5)), forKey: "inputOffset")
container.addSublayer(backdrop); container.addSublayer(mapLayer); container.filters = [filter]
// Haptics and gesture, Telegram conventions
let haptic = HapticFeedback(); haptic.prepareTap()          // touch-down
if crossedEdgeOn { haptic.tap() }                           // selection tick per half-turn (rate-limit)
haptic.impact(.soft, intensity: landingIntensity)           // 0...1 from landing speed
avatarContainer.view.disablesInteractiveTransitionGestureRecognizer = true
```

---

## 5. Open-source replicas and UI kits (licenses)

| Project | What | License | Use |
|---|---|---|---|
| [TelegramMessenger/Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) | Official iOS app | GPL v2+ ([telegram.org/apps](https://telegram.org/apps#source-code)) | Patch target; icons and metrics source |
| [Ajaxy/telegram-tt](https://github.com/Ajaxy/telegram-tt) / [morethanwords/tweb](https://github.com/morethanwords/tweb) | Telegram Web A / K | GPL-3.0 | Web avatar/profile code reference |
| [DrKLO/Telegram](https://github.com/DrKLO/Telegram) | Android | GPL-2.0 | — |
| [telegram-mini-apps-dev/TelegramUI](https://github.com/telegram-mini-apps-dev/TelegramUI) | React kit "inspired by Telegram interface" | MIT | Cells and lists; pre-Liquid-Glass styling |
| [konstaui/konsta](https://github.com/konstaui/konsta) v5 | Tailwind mobile UI, "updated iOS 26 … look and feel" ([v5.0.0](https://github.com/konstaui/konsta/releases/tag/v5.0.0)) | MIT | iOS-26 navbar, segmented and tab-bar CSS reference |
| [framework7io/framework7](https://github.com/framework7io/framework7) v9 | "all new iOS 26 styles across all components" ([migration](https://cdn.framework7.io/docs/migration-from-v8-to-v9.html)) | MIT | Same |
| [ionic-team/ionic-framework](https://github.com/ionic-team/ionic-framework) | iOS-mode components | MIT | Fallback |
| [iyinchao/liquid-glass-studio](https://github.com/iyinchao/liquid-glass-studio) | WebGL2/WebGPU glass, SDF + springs | MIT | **Shader base** |
| [naughtyduk/liquidGL](https://github.com/naughtyduk/liquidGL) | WebGPU/WebGL glass panes, DOM snapshot | MIT (code) | Bevel and aberration ideas |
| [rdev/liquid-glass-react](https://github.com/rdev/liquid-glass-react) | SVG glass React component | MIT | Aberration filter recipe |
| [shuding/liquid-glass](https://github.com/shuding/liquid-glass) | Copy-paste SVG glass | MIT | Minimal map generator |
| [dashersw/liquid-glass-js](https://github.com/dashersw/liquid-glass-js) | WebGL2 glass components; page sampled via html2canvas | MIT | — |
| [ybouane/liquidglass](https://github.com/ybouane/liquidglass) | WebGL1 glass for any element (html-to-image capture; Chrome, Firefox, Safari) | MIT per README and package.json, but no LICENSE file | Ideas; ask before copying |
| [ryanashcraft/FabBar](https://github.com/ryanashcraft/FabBar) | iOS 26 tab bar plus FAB: SwiftUI API over internal UIKit hierarchy manipulation | MIT | Native reference |
| [Sergey-Shteyman/Avatar-With-Dynamic-Island-SwiftUI](https://github.com/Sergey-Shteyman/Avatar-With-Dynamic-Island-SwiftUI), [eriffanani/Telegram-Dynamic-Island](https://github.com/eriffanani/Telegram-Dynamic-Island), [flutter_metaballs](https://github.com/DmitriiProshutinskii/flutter_metaballs) | Telegram avatar → Dynamic Island clones | **none** | Look only |
| [jtrivedi/Wave](https://github.com/jtrivedi/Wave), [super-ultra/ScrollMechanics](https://github.com/super-ultra/ScrollMechanics), [nathangitter/fluid-interfaces](https://github.com/nathangitter/fluid-interfaces) | Springs, decay, rubber band | MIT / MIT / Apache-2.0 | Physics code |
| Apple [Design Resources](https://developer.apple.com/design/resources/) | iOS 27 UI Kit ([Figma](https://www.figma.com/community/file/1651309003795292092/ios-and-ipados-27)), SF Symbols 27 | Apple terms (inside the kit) | Measurements only; don't redistribute |

---

## 6. SF Pro font

- **Download**: [developer.apple.com/fonts](https://developer.apple.com/fonts/) → [SF-Pro.dmg](https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg). It is about 218 MB; not downloaded here.
- **License** ("Apple San Francisco Font", text on the same page):
  - "to be used **solely for creating mock-ups of user interfaces** to be used in software products running on Apple's iOS, OS X or tvOS". This includes "screen shots, images, mock-ups … digital and/or print".
  - "only if you are a registered Apple Developer".
  - "You may not **embed** the Apple Font in any software programs or other products".
  - You may not make it "available over a network where it could be run or used by multiple computers".
  - "you may not use the Apple Font to, create, develop, display or otherwise distribute any documentation, artwork, **website content** or any other work product". This is subject to the mock-up exception above, so a *publicly hosted* web demo must not depend on SF font files.
- **Implication**: never commit or serve SF Pro files (no `@font-face`, no public repo). A local mockup or recording of an iOS UI is within scope. The submitted *code* must not bundle the font.
- **Alternatives**:
  - CSS `-apple-system` / `system-ui` renders the real system SF on Apple devices without shipping it ([WebKit blog](https://webkit.org/blog/3709/using-the-system-font-in-web-content/)). Telegram iOS itself uses the system font: `UIFont.systemFont(ofSize:weight:)` in `submodules/Display/Source/Font.swift`.
  - Off-Apple fallback: [Inter](https://github.com/rsms/inter) (SIL OFL 1.1). v4.0 adds "Display" designs on an `opsz` axis ([release](https://github.com/rsms/inter/releases/tag/v4.0)), handy for mimicking SF's Text/Display optical sizes.
- Icons: SF Symbols ship under Apple's own terms (in the app). For the replica, prefer Telegram's GPL icon assets from Telegram-iOS, keeping that code GPL-compatible.
