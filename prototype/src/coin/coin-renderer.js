// WebGL2 host for the glass coin shader. Owns textures (photos, emblem, cover) and
// turns a GlassCoin state into uniforms. The Metal host (ios/…/GlassCoinLayer.swift)
// computes exactly the same uniforms.

import { coinVertexShader, coinFragmentShader } from './coin-shader.js';

export const CoinLook = {
  radius: 50,             // avatar radius (pt) = glass radius: nothing frames the photo
  halfThickness: 3.4,     // h at full glass: a 6.8 pt sheet (all an edge-on turn shows)
  rimWidth: 7.5,          // w: rounded edge band inside the photo's circle: the photo visibly folds into it
  liftZ: 22,              // pt toward the eye at full lift (≈ ×1.044 with eyeDistance 520)
  eyeDistance: 520,       // CATransform3D m34 = −1/520
  ior: 1.5,
  dispersion: 0.03,
  shadowDark: 0.16,       // minimal, centred (designer video: "shadow minimal")
  shadowLight: 0.10,
  glow: 0.10,             // light of a tinted glass around the avatar
  restGlass: 0.16,        // a tinted avatar keeps a hint of its glass at rest
  lightIntensity: 1.0,
  shutter: 0.5,           // 180° shutter for motion blur
};

function compile(gl, type, src) {
  const s = gl.createShader(type);
  gl.shaderSource(s, src);
  gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
    const log = gl.getShaderInfoLog(s);
    const lines = src.split('\n').map((l, i) => `${i + 1}: ${l}`).join('\n');
    throw new Error(`shader compile failed: ${log}\n${lines.slice(0, 200)}`);
  }
  return s;
}

export class CoinRenderer {
  // preserve: keep the drawing buffer between frames (recordings read it back); a phone
  // doesn't need the extra copy per frame.
  constructor(canvas, { preserve = false } = {}) {
    this.canvas = canvas;
    this.sources = new Map();   // face key → image, to rebuild the textures after a lost context
    this.cover = null;          // { canvas, version } last uploaded
    this.maxSamples = 8;        // motion-blur samples; lowered on a phone that can't keep up
    this.lost = false;
    // iOS drops WebGL contexts under memory pressure or in the background: rebuild when it
    // comes back instead of leaving a frozen avatar.
    canvas.addEventListener('webglcontextlost', (e) => {
      e.preventDefault();
      this.lost = true;
    });
    canvas.addEventListener('webglcontextrestored', () => {
      this.init();
      this.lost = false;
      this.onRestore?.();
    });
    const gl = canvas.getContext('webgl2', { premultipliedAlpha: true, alpha: true, antialias: false, preserveDrawingBuffer: preserve });
    if (!gl) throw new Error('WebGL2 unavailable');
    this.gl = gl;
    this.init();
  }

  init() {
    const gl = this.gl;
    const program = gl.createProgram();
    gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, coinVertexShader));
    gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, coinFragmentShader));
    gl.bindAttribLocation(program, 0, 'aPosition');
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
    this.program = program;
    this.u = {};
    const n = gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) {
      const info = gl.getActiveUniform(program, i);
      this.u[info.name] = gl.getUniformLocation(program, info.name);
    }
    const vao = gl.createVertexArray();
    gl.bindVertexArray(vao);
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    this.vao = vao;
    this.textures = new Map();
    for (const [key, source] of this.sources) this.textures.set(key, this.makeTexture(source));
    this.coverTexture = null;
    this.coverVersion = -1;
    if (this.cover) this.updateCover(this.cover.canvas, this.cover.version);
  }

  makeTexture(source, { mipmaps = true } = {}) {
    const gl = this.gl;
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL, gl.NONE);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, source);
    if (mipmaps) {
      gl.generateMipmap(gl.TEXTURE_2D);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    } else {
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    }
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return t;
  }

  setFace(key, source) {
    this.faceSize = source.naturalWidth || source.width || 900;
    this.sources.set(key, source);
    if (this.lost) return;
    const old = this.textures.get(key);
    if (old) this.gl.deleteTexture(old);
    this.textures.set(key, this.makeTexture(source));
  }

  updateCover(canvas, version) {
    this.cover = { canvas, version };
    if (this.lost) return;
    if (version === this.coverVersion && this.coverTexture) return;
    const gl = this.gl;
    if (!this.coverTexture) {
      this.coverTexture = this.makeTexture(canvas, { mipmaps: false });
    } else {
      gl.bindTexture(gl.TEXTURE_2D, this.coverTexture);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, canvas);
    }
    this.coverVersion = version;
  }

  // frame: { sizePt: {w,h}, pxPerPt, coverRectPt: [x,y,w,h] (y-down, canvas pt),
  //          envLow, envHigh, tint (arrays), dark, envRotation }
  render(state, frame) {
    const gl = this.gl;
    if (this.lost) return;
    const L = CoinLook;
    const pxW = Math.round(frame.sizePt.w * frame.pxPerPt);
    const pxH = Math.round(frame.sizePt.h * frame.pxPerPt);
    if (this.canvas.width !== pxW || this.canvas.height !== pxH) {
      this.canvas.width = pxW;
      this.canvas.height = pxH;
    }
    gl.viewport(0, 0, pxW, pxH);
    gl.useProgram(this.program);
    gl.bindVertexArray(this.vao);
    gl.disable(gl.BLEND);

    const lift = Math.max(-0.4, Math.min(1.3, state.lift));
    const tint = frame.glassTint || 0;
    const active = state.glass !== undefined ? state.glass : Math.max(0, Math.min(1, lift));
    const glass = Math.max(active, L.restGlass * tint);
    const h = Math.max(0.04, L.halfThickness * glass);
    const w = Math.max(h, L.rimWidth * glass);
    const liftZ = L.liftZ * lift;

    const cy = Math.cos(state.yaw), sy = Math.sin(state.yaw);
    const cp = Math.cos(state.pitch), sp = Math.sin(state.pitch);
    // R = Rx(pitch) · Ry(yaw) — the shader rebuilds it per motion-blur sample
    const r02 = sy, r12 = -sp * cy, r22 = cp * cy;
    // Wrapped: the angle grows by π per face and fast-math sin/cos want small arguments.
    const TAU = 2 * Math.PI;
    gl.uniform1f(this.u.uYaw, state.yaw - TAU * Math.round(state.yaw / TAU));
    gl.uniform1f(this.u.uPitch, state.pitch);
    const dt = frame.dt || 1 / 60;
    const span = (state.yawVelocity || 0) * dt * L.shutter;
    const samples = Math.max(1, Math.min(this.maxSamples, Math.ceil(Math.abs(span) / (5 * Math.PI / 180))));
    gl.uniform1f(this.u.uYawSpan, samples > 1 ? span : 0);
    gl.uniform1i(this.u.uSamples, samples);
    gl.uniform1f(this.u.uLightIntensity, frame.lightIntensity ?? L.lightIntensity);

    const centerX = frame.sizePt.w / 2 + state.offsetX;
    const centerY = frame.sizePt.h / 2 - state.offsetY; // y up
    gl.uniform1f(this.u.uPxPerPt, frame.pxPerPt);
    gl.uniform2f(this.u.uCenterPt, centerX, centerY);
    gl.uniform2f(this.u.uCanvasSizePt, frame.sizePt.w, frame.sizePt.h);
    gl.uniform1f(this.u.uCoinZ, -h + liftZ);
    gl.uniform1f(this.u.uRadius, L.radius);
    gl.uniform1f(this.u.uHalfThickness, h);
    gl.uniform1f(this.u.uRimWidth, w);
    gl.uniform1f(this.u.uGlass, glass);
    gl.uniform1f(this.u.uEyeDistance, L.eyeDistance);
    gl.uniform1f(this.u.uIor, L.ior);
    gl.uniform1f(this.u.uDispersion, L.dispersion);
    gl.uniform3fv(this.u.uEnvLow, frame.envLow);
    gl.uniform3fv(this.u.uEnvHigh, frame.envHigh);
    gl.uniform1f(this.u.uEnvRotation, frame.envRotation || 0);
    const glassColor = frame.glassColor || [1, 1, 1];
    gl.uniform3fv(this.u.uGlassColor, glassColor);
    gl.uniform1f(this.u.uGlassTint, tint);
    gl.uniform1f(this.u.uEdgeBoost, frame.flash || 0);
    gl.uniform4f(this.u.uCoverRectPt, ...frame.coverRectPt);

    // Shadow: one soft ellipse centred under the glass (the coin's silhouette, turned),
    // only while it is lifted. Nothing drops below it, so every edge reads the same.
    const nx = r02, ny = r12, nz = r22;            // coin normal in world (3rd column)
    const nxy = Math.hypot(nx, ny);
    const Rc = L.radius;
    const angle = nxy > 1e-4 ? Math.atan2(ny, nx) : 0;
    const liftPos = Math.max(0, liftZ);
    const shadowCenterY = -(0.5 + liftPos * 0.08);
    const shadowSigma = 2.5 + liftPos * 0.25;
    gl.uniform2f(this.u.uShadowCenter, 0, shadowCenterY);
    gl.uniform2f(this.u.uShadowAxes, Math.max(2, Rc * Math.abs(nz) + 2 * h * nxy), Rc);
    gl.uniform1f(this.u.uShadowAngle, angle);
    gl.uniform1f(this.u.uShadowSigma, shadowSigma);
    gl.uniform1f(this.u.uShadowStrength, active * Math.max(0, Math.min(1, lift)) * (frame.dark ? L.shadowDark : L.shadowLight));
    // Glow: the light of a tinted glass (a hint at rest, more while held) and the
    // flash of a colour change.
    const glow = tint * (L.glow * Math.max(glass, 0.6) + 0.55 * (frame.flash || 0)) * (frame.dark ? 1 : 0.7);
    gl.uniform3fv(this.u.uGlowColor, glassColor);
    gl.uniform1f(this.u.uGlow, glow);
    // Conservative screen-space bounds (pt) so empty pixels exit early.
    const Rs = Math.hypot(L.radius, h);
    const zc = -h + liftZ;
    const coinBound = (Rs * L.eyeDistance) / Math.max(1, L.eyeDistance - zc - Rs) + 3 / frame.pxPerPt + 1;
    const shadowReach = Math.abs(shadowCenterY) + Rc + shadowSigma * 3 + 4;
    const glowReach = glow > 0 ? (L.radius + 16) * 1.75 : 0;
    gl.uniform1f(this.u.uCoinBound, coinBound);
    gl.uniform1f(this.u.uInfluence, Math.max(coinBound, active > 0 ? shadowReach : 0, glowReach));

    const texA = this.textures.get(state.sideA) || this.textures.get(0);
    const texB = this.textures.get(state.sideB) || this.textures.get(0);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, texA);
    gl.uniform1i(this.u.uPhotoA, 0);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, texB);
    gl.uniform1i(this.u.uPhotoB, 1);
    gl.activeTexture(gl.TEXTURE2);
    gl.bindTexture(gl.TEXTURE_2D, this.coverTexture);
    gl.uniform1i(this.u.uCover, 2);
    // texels per screen pixel → mip level; foreshortening (|n_z|) compresses the face further
    const texSize = this.faceSize || 900;
    const pixelsAcross = 2 * L.radius * frame.pxPerPt * Math.max(0.2, Math.abs(r22));
    gl.uniform1f(this.u.uPhotoLod, Math.max(0, Math.log2(texSize / pixelsAcross)));

    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }
}
