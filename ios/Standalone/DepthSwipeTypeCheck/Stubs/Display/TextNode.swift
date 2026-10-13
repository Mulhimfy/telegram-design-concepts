import UIKit
import CoreText
import AsyncDisplayKit

// Signature stubs of Display/Source/TextNode.swift @ f1dd7a2 — only what DepthSwipe uses:
//   TextNodeLayout.attributedString (380), truncated (393), enumerateRenderedLines(in:_:) (784)
//   TextNode.RenderContentTypes (1241), TextNode.DrawingParameters (1254), cachedLayout (1277),
//   class func draw(_:withParameters:isCancelled:isRasterizing:) (2346)

public final class TextNodeLayout: NSObject {
    public let attributedString: NSAttributedString?
    public let size: CGSize
    public let truncated: Bool

    public init(attributedString: NSAttributedString?, size: CGSize, truncated: Bool) {
        self.attributedString = attributedString
        self.size = size
        self.truncated = truncated
        super.init()
    }

    public func enumerateRenderedLines(in bounds: CGRect, _ body: (CTLine, CGPoint) -> Void) {
    }
}

open class TextNode: ASDisplayNode {
    public struct RenderContentTypes: OptionSet {
        public var rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let text = RenderContentTypes(rawValue: 1 << 0)
        public static let emoji = RenderContentTypes(rawValue: 1 << 1)

        public static let all: RenderContentTypes = [.text, .emoji]
    }

    public final class DrawingParameters: NSObject {
        let cachedLayout: TextNodeLayout?
        let renderContentTypes: RenderContentTypes

        public init(cachedLayout: TextNodeLayout?, renderContentTypes: RenderContentTypes) {
            self.cachedLayout = cachedLayout
            self.renderContentTypes = renderContentTypes

            super.init()
        }
    }

    public internal(set) var cachedLayout: TextNodeLayout?

    override public init() {
        super.init()
    }

    @objc override public class func draw(_ bounds: CGRect, withParameters parameters: Any?, isCancelled: () -> Bool, isRasterizing: Bool) {
    }
}
