import Foundation
import UIKit

// Stub of submodules/AppBundle (Objective-C) @ f1dd7a2, PublicHeaders/AppBundle/AppBundle.h:
//   NSBundle * _Nonnull getAppBundle(void);
//   @interface UIImage (AppBundle)
//   - (instancetype _Nullable)initWithBundleImageName:(NSString * _Nonnull)bundleImageName;

public func getAppBundle() -> Bundle {
    return Bundle.main
}

public extension UIImage {
    convenience init?(bundleImageName: String) {
        self.init(named: bundleImageName, in: getAppBundle(), compatibleWith: nil)
    }
}
