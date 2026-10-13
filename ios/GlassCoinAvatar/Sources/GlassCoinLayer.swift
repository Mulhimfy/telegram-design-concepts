import Foundation
import UIKit
import Metal
import MetalKit
import Display
import MetalEngine

/// The look of the glass avatar — the same constants as `CoinLook` in prototype/src/coin/coin-renderer.js
/// (for the 100 pt avatar; `GlassCoinAvatarNode.update(size:avatarRadius:...)` scales the lengths with it).
public struct GlassCoinLook: Equatable {
    /// Avatar radius = glass radius: nothing frames the photo.
    public var radius: CGFloat = 50.0
    /// h at full glass: a 6.8 pt sheet (all an edge-on turn shows).
    public var halfThickness: CGFloat = 3.4
    /// w: the rounded edge band inside the photo's circle: the photo visibly folds into it. Always w ≥ h.
    public var rimWidth: CGFloat = 7.5
    /// How far the glass moves toward the eye at full lift (≈ ×1.044 with `eyeDistance`).
    public var liftZ: CGFloat = 22.0
    /// CATransform3D m34 = -1 / eyeDistance.
    public var eyeDistance: CGFloat = 520.0
    public var indexOfRefraction: CGFloat = 1.5
    public var dispersion: CGFloat = 0.03
    /// Minimal, centred shadow (designer video: "shadow minimal").
    public var shadowStrengthDark: CGFloat = 0.16
    public var shadowStrengthLight: CGFloat = 0.10
    /// Light of a tinted glass around the avatar.
    public var glow: CGFloat = 0.10
    /// A tinted avatar keeps a hint of its glass at rest: glass = max(active, restGlass · tint).
    public var restGlass: CGFloat = 0.16
    public var lightIntensity: CGFloat = 1.0
    /// 180° shutter for the motion blur of fast spins.
    public var shutter: CGFloat = 0.5

    public init() {
    }
}

/// Must match `GlassCoinUniforms` in GlassCoin.metal member for member (the table there maps each lane to its GLSL
/// uniform): 14 × SIMD4<Float> = 224 bytes. SIMD4<Float> has the size and alignment of Metal's float4 (16 bytes), so
/// both sides lay the struct out identically with no padding; `stride` is checked in `update(context:)`.
struct GlassCoinUniforms {
    /// boundsSize.xy (pt), renderSize.zw (px, without the edge inset)
    var frame0 = SIMD4<Float>()
    /// edgeInset (px), pixelsPerPoint, coin centre in layer points (x, y down) — uPxPerPt, uCenterPt
    var frame1 = SIMD4<Float>()
    /// yaw, pitch, yawSpan (motion blur), sample count — uYaw, uPitch, uYawSpan, uSamples
    var pose = SIMD4<Float>()
    /// coinZ, radius R, halfThickness h, glass — uCoinZ, uRadius, uHalfThickness, uGlass
    var coin = SIMD4<Float>()
    /// rimWidth w, photo LOD, coinBound, influence — uRimWidth, uPhotoLod, uCoinBound, uInfluence
    var edge = SIMD4<Float>()
    /// eyeDistance, ior, dispersion, lightIntensity — uEyeDistance, uIor, uDispersion, uLightIntensity
    var optics = SIMD4<Float>()
    /// envRotation, edgeBoost, glassTint, glow — uEnvRotation, uEdgeBoost, uGlassTint, uGlow
    var light = SIMD4<Float>()
    /// rgb — uEnvLow
    var envLow = SIMD4<Float>()
    /// rgb — uEnvHigh
    var envHigh = SIMD4<Float>()
    /// rgb — uGlassColor
    var glassColor = SIMD4<Float>()
    /// rgb — uGlowColor
    var glowColor = SIMD4<Float>()
    /// cover texture rect in layer points: x, y (top, y down), w, h — uCoverRectPt
    var coverRect = SIMD4<Float>()
    /// centre.xy (pt, y up, relative to the coin centre), axes.zw — uShadowCenter, uShadowAxes
    var shadow0 = SIMD4<Float>()
    /// angle, sigma, strength, unused — uShadowAngle, uShadowSigma, uShadowStrength
    var shadow1 = SIMD4<Float>()

    static let expectedStride = 14 * 16
}

private final class GlassCoinBundleMarker: NSObject {
}

private let glassCoinLibraryLock = NSLock()
private var glassCoinLibraryValue: (device: MTLDevice, library: MTLLibrary)?

/// The shaders, compiled at build time into GlassCoinAvatarMetalSourcesBundle's default.metallib.
private func glassCoinMetalLibrary(device: MTLDevice) -> MTLLibrary? {
    glassCoinLibraryLock.lock()
    defer {
        glassCoinLibraryLock.unlock()
    }
    if let glassCoinLibraryValue, glassCoinLibraryValue.device === device {
        return glassCoinLibraryValue.library
    }
    let mainBundle = Bundle(for: GlassCoinBundleMarker.self)
    guard let path = mainBundle.path(forResource: "GlassCoinAvatarMetalSourcesBundle", ofType: "bundle"), let bundle = Bundle(path: path) else {
        return nil
    }
    guard let library = try? device.makeDefaultLibrary(bundle: bundle) else {
        return nil
    }
    glassCoinLibraryValue = (device, library)
    return library
}

private let glassCoinPipelineLock = NSLock()
private var glassCoinPipelineValue: MTLRenderPipelineState?

/// Compiles on the calling thread if the pipeline is not ready yet; `prewarmGlassCoin()` makes it in
/// the background before the first touch, so the first frame never compiles.
private func glassCoinPipelineState(device: MTLDevice) -> MTLRenderPipelineState? {
    glassCoinPipelineLock.lock()
    let cached = glassCoinPipelineValue
    glassCoinPipelineLock.unlock()
    if let cached {
        return cached
    }
    guard let library = glassCoinMetalLibrary(device: device), let vertexFunction = library.makeFunction(name: "glassCoinVertex"), let fragmentFunction = library.makeFunction(name: "glassCoinFragment") else {
        return nil
    }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertexFunction
    descriptor.fragmentFunction = fragmentFunction
    // Every pixel of the allocation is written (premultiplied), so no blending.
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    guard let pipelineState = MetalEngine.shared.pipelineCache.makeRenderPipelineState(descriptor: descriptor) else {
        return nil
    }
    glassCoinPipelineLock.lock()
    glassCoinPipelineValue = pipelineState
    glassCoinPipelineLock.unlock()
    return pipelineState
}

/// Builds the pipeline in the background (called when a profile with a glass avatar appears).
public func prewarmGlassCoin() {
    DispatchQueue.global(qos: .userInitiated).async {
        let _ = glassCoinPipelineState(device: MetalEngine.shared.device)
    }
}

/// MetalEngine keeps one render state per type.
final class GlassCoinRenderState: RenderToLayerState {
    let pipelineState: MTLRenderPipelineState

    init?(device: MTLDevice) {
        guard let pipelineState = glassCoinPipelineState(device: device) else {
            return nil
        }
        self.pipelineState = pipelineState
    }
}

/// Renders the glass avatar for a `GlassCoinState` into a MetalEngine surface. The layer is larger than the avatar
/// (the glass tilts, lifts, translates and casts a shadow and a glow), centred on it.
///
/// The cover behind the avatar is refracted from a snapshot taken when the interaction starts: it does not change
/// while the glass is held, and a snapshot works on every iOS version (the live `CABackdropLayer` + `displacementMap`
/// route of LiquidGlassShapes is iOS 26-only and carries one offset per pixel, which loses the chromatic dispersion).
public final class GlassCoinLayer: SimpleLayer, MetalEngineSubject {
    public var internalData: MetalEngineSubjectInternalData?

    public var look = GlassCoinLook() {
        didSet {
            if self.look != oldValue {
                self.setNeedsUpdate()
            }
        }
    }
    public var isDarkAppearance: Bool = true {
        didSet {
            if self.isDarkAppearance != oldValue {
                self.setNeedsUpdate()
            }
        }
    }
    /// Environment colours derived from the profile colour (see `GlassCoinEnvironment`).
    public var environment = GlassCoinEnvironment.neutral(isDark: true) {
        didSet {
            if self.environment != oldValue {
                self.setNeedsUpdate()
            }
        }
    }
    /// The glass colour the user picked, rgb 0…1 (`uGlassColor`; the glow around the avatar takes it too). Clear glass
    /// keeps the last colour and sets `glassTint` to 0, so a change to Clear fades the tint instead of the colour.
    public var glassColor = SIMD3<Float>(1.0, 1.0, 1.0) {
        didSet {
            if self.glassColor != oldValue {
                self.setNeedsUpdate()
            }
        }
    }
    /// 0 clear … 1 fully tinted (`uGlassTint`); it also keeps `look.restGlass · glassTint` of glass at rest and
    /// scales the glow.
    public var glassTint: CGFloat = 0.0 {
        didSet {
            if self.glassTint != oldValue {
                self.setNeedsUpdate()
            }
        }
    }
    /// The flash of a colour change, 0…0.9: extra edge light (`uEdgeBoost`) and glow.
    public var flash: CGFloat = 0.0 {
        didSet {
            if self.flash != oldValue {
                self.setNeedsUpdate()
            }
        }
    }
    /// Duration of the frame being drawn, for the motion blur span.
    public var frameDuration: Double = 1.0 / 60.0

    public var state: GlassCoinState? {
        didSet {
            self.setNeedsUpdate()
        }
    }

    private let contentLayer: MetalEngineSubjectLayer
    private var faceTextures: [GlassCoinFaceContent: MTLTexture] = [:]
    private var coverTexture: MTLTexture?
    /// The cover snapshot's frame in this layer's coordinates (points).
    private var coverFrame: CGRect = .zero
    private var faceTextureSize: CGFloat = 640.0

    override public init() {
        self.contentLayer = MetalEngineSubjectLayer()
        super.init()
        self.isOpaque = false
        self.addSublayer(self.contentLayer)
    }

    override public init(layer: Any) {
        guard let layer = layer as? GlassCoinLayer else {
            preconditionFailure()
        }
        self.contentLayer = layer.contentLayer
        super.init(layer: layer)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// rgb 0…1 of a colour, in the colour space the shader works in (the texture samples are not linearized either).
    public static func rgb(_ color: UIColor) -> SIMD3<Float> {
        var r: CGFloat = 0.0, g: CGFloat = 0.0, b: CGFloat = 0.0, a: CGFloat = 0.0
        if !color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var white: CGFloat = 0.0
            if color.getWhite(&white, alpha: &a) {
                r = white
                g = white
                b = white
            }
        }
        return SIMD3<Float>(Float(max(0.0, min(1.0, r))), Float(max(0.0, min(1.0, g))), Float(max(0.0, min(1.0, b))))
    }

    /// A picked glass colour (tint 1), or clear glass (tint 0; the colour is kept for the fade).
    public func setGlassColor(_ color: UIColor?) {
        if let color {
            self.glassColor = GlassCoinLayer.rgb(color)
            self.glassTint = 1.0
        } else {
            self.glassTint = 0.0
        }
    }

    /// Lays the sublayer out for the current bounds; call after changing the frame.
    public func updateLayout() {
        self.contentLayer.frame = CGRect(origin: CGPoint(), size: self.bounds.size)
        self.setNeedsUpdate()
    }

    public func releaseSurfaces() {
        self.contentLayer.releaseSurface()
    }

    private static func makeTexture(_ image: CGImage, mipmaps: Bool) -> MTLTexture? {
        let loader = MTKTextureLoader(device: MetalEngine.shared.device)
        return try? loader.newTexture(cgImage: image, options: [
            .SRGB: false as NSNumber,
            .generateMipmaps: mipmaps as NSNumber,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue as NSNumber,
            .textureStorageMode: MTLStorageMode.private.rawValue as NSNumber
        ])
    }

    /// The photo or the back photo for a face. Square images; the card shows their inscribed circle.
    public func setFaceImage(_ image: UIImage?, for content: GlassCoinFaceContent) {
        guard let cgImage = image?.cgImage else {
            if self.faceTextures.removeValue(forKey: content) != nil {
                self.setNeedsUpdate()
            }
            return
        }
        if let texture = GlassCoinLayer.makeTexture(cgImage, mipmaps: true) {
            self.faceTextureSize = CGFloat(texture.width)
            self.faceTextures[content] = texture
            self.setNeedsUpdate()
        }
    }

    public func hasFaceImage(for content: GlassCoinFaceContent) -> Bool {
        return self.faceTextures[content] != nil
    }

    /// Frees every face except `keep`.
    public func retainFaceImages(_ keep: Set<GlassCoinFaceContent>) {
        self.faceTextures = self.faceTextures.filter { keep.contains($0.key) }
    }

    public func removeAllFaceImages() {
        self.faceTextures.removeAll()
        self.setNeedsUpdate()
    }

    /// The profile cover as it is behind the avatar, and where that image sits in this layer (points).
    public func setCoverImage(_ image: UIImage?, frame: CGRect) {
        self.coverFrame = frame
        if let cgImage = image?.cgImage {
            self.coverTexture = GlassCoinLayer.makeTexture(cgImage, mipmaps: false)
        } else {
            self.coverTexture = nil
        }
        self.setNeedsUpdate()
    }

    public func update(context: MetalEngineSubjectContext) {
        let size = self.bounds.size
        guard size.width > 0.0, size.height > 0.0, let state = self.state else {
            return
        }
        // The face in front must be loaded (until it is, the last frame stays); the side facing away can stand in
        // for the other until it is loaded too.
        let front: GlassCoinFaceContent = cos(state.yaw) >= 0.0 ? state.sideA : state.sideB
        guard self.faceTextures[front] != nil, let photoA = self.faceTextures[state.sideA] ?? self.faceTextures[state.sideB] else {
            return
        }
        let photoB: MTLTexture = self.faceTextures[state.sideB] ?? photoA
        let cover: MTLTexture = self.coverTexture ?? photoA
        let scale = UIScreenScale
        let renderSize = RenderSize(width: max(1, Int(ceil(size.width * scale))), height: max(1, Int(ceil(size.height * scale))))
        let edgeInset = 2
        let uniforms = self.makeUniforms(state: state, size: size, renderSize: renderSize, edgeInset: edgeInset, pixelsPerPoint: scale)
        let hasCover = self.coverTexture != nil
        assert(MemoryLayout<GlassCoinUniforms>.stride == GlassCoinUniforms.expectedStride)

        let spec = RenderLayerSpec(size: renderSize, edgeInset: edgeInset, prefersDedicatedSurface: true)
        context.renderToLayer(spec: spec, state: GlassCoinRenderState.self, layer: self.contentLayer, commands: { encoder, placement in
            let effectiveRect = placement.effectiveRect
            var rect = SIMD4<Float>(Float(effectiveRect.minX), Float(effectiveRect.minY), Float(effectiveRect.width), Float(effectiveRect.height))
            encoder.setVertexBytes(&rect, length: MemoryLayout<SIMD4<Float>>.size, index: 0)

            var uniforms = uniforms
            if !hasCover {
                // No snapshot yet: the rays that pass the photo see its own colour instead of the cover.
                uniforms.coverRect = SIMD4<Float>(-1e4, -1e4, 2e4, 2e4)
            }
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GlassCoinUniforms>.stride, index: 0)
            encoder.setFragmentTexture(photoA, index: 0)
            encoder.setFragmentTexture(photoB, index: 1)
            encoder.setFragmentTexture(cover, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        })
    }

    /// Mirrors `CoinRenderer.render()` (prototype/src/coin/coin-renderer.js) uniform for uniform.
    private func makeUniforms(state: GlassCoinState, size: CGSize, renderSize: RenderSize, edgeInset: Int, pixelsPerPoint: CGFloat) -> GlassCoinUniforms {
        let look = self.look
        let isDark = self.isDarkAppearance
        let lift = max(-0.4, min(1.3, state.lift))
        let tint = Double(max(0.0, min(1.0, self.glassTint)))
        let flash = Double(max(0.0, self.flash))
        // `active` is the interaction's glass; a tinted glass never goes below its rest hint.
        let active = state.glass
        let glass = max(active, Double(look.restGlass) * tint)
        let h = max(0.04, Double(look.halfThickness) * glass)
        let w = max(h, Double(look.rimWidth) * glass)
        let liftZ = Double(look.liftZ) * lift
        let radius = Double(look.radius)
        let eyeDistance = Double(look.eyeDistance)
        let pxPerPt = Double(pixelsPerPoint)

        // R = Rx(pitch) · Ry(yaw); its third column is the glass normal in world space.
        let cy = cos(state.yaw)
        let sy = sin(state.yaw)
        let cp = cos(state.pitch)
        let sp = sin(state.pitch)
        let nx = sy
        let ny = -sp * cy
        let nz = cp * cy
        let nxy = (nx * nx + ny * ny).squareRoot()

        let span = state.yawVelocity * self.frameDuration * Double(look.shutter)
        let samples = max(1, min(8, Int(ceil(abs(span) / (5.0 * Double.pi / 180.0)))))

        // Coin centre in layer points, y down (the web's canvas is y up: centreY = h/2 − offsetY there).
        let center = CGPoint(x: size.width * 0.5 + state.offset.x, y: size.height * 0.5 + state.offset.y)

        // Shadow: one soft ellipse centred under the glass (its silhouette, turned), only while it is lifted.
        let shadowAngle = nxy > 1e-4 ? atan2(ny, nx) : 0.0
        let liftPositive = max(0.0, liftZ)
        let shadowCenterY = -(0.5 + liftPositive * 0.08)
        let shadowSigma = 2.5 + liftPositive * 0.25
        let shadowStrength = active * max(0.0, min(1.0, lift)) * Double(isDark ? look.shadowStrengthDark : look.shadowStrengthLight)

        // Glow: the light of a tinted glass (a hint at rest, more while held) and the flash of a colour change.
        let glow = tint * (Double(look.glow) * max(glass, 0.6) + 0.55 * flash) * (isDark ? 1.0 : 0.7)

        // Conservative screen-space bounds (pt) so empty pixels exit early.
        let rs = (radius * radius + h * h).squareRoot()
        let zc = -h + liftZ
        let coinBound = (rs * eyeDistance) / max(1.0, eyeDistance - zc - rs) + 3.0 / pxPerPt + 1.0
        let shadowReach = abs(shadowCenterY) + radius + shadowSigma * 3.0 + 4.0
        let glowReach = glow > 0.0 ? (radius + 16.0) * 1.75 : 0.0
        let influence = max(coinBound, active > 0.0 ? shadowReach : 0.0, glowReach)

        // Texels per screen pixel → mip level; foreshortening (|n_z|) compresses the face further.
        let photoLod = max(0.0, log2(Double(self.faceTextureSize) / (2.0 * radius * pxPerPt * max(0.2, abs(nz)))))

        let glassColor = SIMD4<Float>(self.glassColor.x, self.glassColor.y, self.glassColor.z, 0.0)

        var u = GlassCoinUniforms()
        u.frame0 = SIMD4<Float>(Float(size.width), Float(size.height), Float(renderSize.width), Float(renderSize.height))
        u.frame1 = SIMD4<Float>(Float(edgeInset), Float(pixelsPerPoint), Float(center.x), Float(center.y))
        // Wrapped: the angle grows by π per face and fast-math sin/cos are accurate on [-π, π].
        u.pose = SIMD4<Float>(Float(remainder(state.yaw, 2.0 * Double.pi)), Float(state.pitch), Float(samples > 1 ? span : 0.0), Float(samples))
        u.coin = SIMD4<Float>(Float(-h + liftZ), Float(radius), Float(h), Float(glass))
        u.edge = SIMD4<Float>(Float(w), Float(photoLod), Float(coinBound), Float(influence))
        u.optics = SIMD4<Float>(Float(eyeDistance), Float(look.indexOfRefraction), Float(look.dispersion), Float(look.lightIntensity))
        u.light = SIMD4<Float>(0.0, Float(flash), Float(tint), Float(glow))
        u.envLow = self.environment.low
        u.envHigh = self.environment.high
        u.glassColor = glassColor
        u.glowColor = glassColor
        u.coverRect = SIMD4<Float>(Float(self.coverFrame.minX), Float(self.coverFrame.minY), Float(self.coverFrame.width), Float(self.coverFrame.height))
        u.shadow0 = SIMD4<Float>(0.0, Float(shadowCenterY), Float(max(2.0, radius * abs(nz) + 2.0 * h * nxy)), Float(radius))
        u.shadow1 = SIMD4<Float>(Float(shadowAngle), Float(shadowSigma), Float(shadowStrength), 0.0)
        return u
    }
}

/// Studio colours for the reflections, derived from the profile colour so the glass belongs to the header it sits on
/// (the same derivation as `envColors` in prototype/src/app.js).
public struct GlassCoinEnvironment: Equatable {
    public var low: SIMD4<Float>
    public var high: SIMD4<Float>

    public init(low: SIMD4<Float>, high: SIMD4<Float>) {
        self.low = low
        self.high = high
    }

    public static func neutral(isDark: Bool) -> GlassCoinEnvironment {
        return isDark
            ? GlassCoinEnvironment(low: SIMD4<Float>(0.06, 0.06, 0.07, 0.0), high: SIMD4<Float>(0.55, 0.56, 0.6, 0.0))
            : GlassCoinEnvironment(low: SIMD4<Float>(0.55, 0.56, 0.6, 0.0), high: SIMD4<Float>(0.97, 0.97, 0.99, 0.0))
    }

    public static func profile(main: UIColor, secondary: UIColor, isDark: Bool) -> GlassCoinEnvironment {
        func vector(_ color: UIColor) -> SIMD4<Float> {
            let rgb = GlassCoinLayer.rgb(color)
            return SIMD4<Float>(rgb.x, rgb.y, rgb.z, 0.0)
        }
        let low = main.withMultiplied(hue: 1.0, saturation: 1.05, brightness: isDark ? 0.55 : 0.8)
        let high = secondary.withMultiplied(hue: 1.0, saturation: 0.6, brightness: 1.45).mixedWith(.white, alpha: 0.38)
        return GlassCoinEnvironment(low: vector(low), high: vector(high))
    }
}
