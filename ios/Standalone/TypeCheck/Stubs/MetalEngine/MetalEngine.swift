import Foundation
import UIKit
import Metal
import Display

// Signature stubs of submodules/MetalEngine/Sources/MetalEngine.swift (the parts GlassCoinLayer uses).

public struct RenderSize: Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct RenderLayerSpec: Equatable {
    public enum PixelFormat {
        case bgra8Unorm
        case rgba16Float
    }

    public var size: RenderSize
    public var edgeInset: Int
    public var pixelFormat: PixelFormat
    public var prefersDedicatedSurface: Bool

    public init(size: RenderSize, edgeInset: Int = 0, pixelFormat: PixelFormat = .bgra8Unorm, prefersDedicatedSurface: Bool = false) {
        self.size = size
        self.edgeInset = edgeInset
        self.pixelFormat = pixelFormat
        self.prefersDedicatedSurface = prefersDedicatedSurface
    }
}

public struct RenderLayerPlacement: Equatable {
    public var effectiveRect: CGRect

    public init(effectiveRect: CGRect) {
        self.effectiveRect = effectiveRect
    }
}

public protocol RenderToLayerState: AnyObject {
    var pipelineState: MTLRenderPipelineState { get }

    init?(device: MTLDevice)
}

open class MetalEngineSubjectLayer: SimpleLayer {
    public func releaseSurface() {
    }
}

public final class MetalEngineSubjectInternalData {
    init() {
    }
}

public final class MetalEngineSubjectContext {
    public func renderToLayer<RenderToLayerStateType: RenderToLayerState>(
        spec: RenderLayerSpec,
        state: RenderToLayerStateType.Type,
        layer: MetalEngineSubjectLayer,
        commands: @escaping (MTLRenderCommandEncoder, RenderLayerPlacement) -> Void
    ) {
    }
}

public protocol MetalEngineSubject: AnyObject {
    var internalData: MetalEngineSubjectInternalData? { get set }

    func setNeedsUpdate()
    func update(context: MetalEngineSubjectContext)
}

public extension MetalEngineSubject {
    func setNeedsUpdate() {
    }
}

public final class MetalPipelineCache {
    public func makeRenderPipelineState(descriptor: MTLRenderPipelineDescriptor) -> MTLRenderPipelineState? {
        return nil
    }
}

public final class MetalEngine {
    public static let shared = MetalEngine()

    public let device: MTLDevice
    public let pipelineCache = MetalPipelineCache()

    private init() {
        self.device = MTLCreateSystemDefaultDevice()!
    }
}
