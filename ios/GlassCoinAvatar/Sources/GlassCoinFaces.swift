import Foundation
import UIKit
import Display

/// A square image filled with `image`, aspect-filled and centred, `size` px across — what the glass card expects for
/// a face (the profile photo, a back photo). The card shows its inscribed circle.
public func glassCoinSquareImage(_ image: UIImage, size: CGFloat = 640.0) -> UIImage? {
    let source = image.size
    guard source.width > 0.0, source.height > 0.0 else {
        return nil
    }
    let scale = max(size / source.width, size / source.height)
    let drawSize = CGSize(width: source.width * scale, height: source.height * scale)
    return generateImage(CGSize(width: size, height: size), opaque: true, scale: 1.0, rotatedContext: { canvasSize, context in
        UIGraphicsPushContext(context)
        image.draw(in: CGRect(x: (canvasSize.width - drawSize.width) / 2.0, y: (canvasSize.height - drawSize.height) / 2.0, width: drawSize.width, height: drawSize.height))
        UIGraphicsPopContext()
    })
}
