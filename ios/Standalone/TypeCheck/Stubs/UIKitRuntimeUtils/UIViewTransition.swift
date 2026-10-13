import UIKit

// Stub of UIKitRuntimeUtils/UIViewController+Navigation.h:
// @property (nonatomic, copy) BOOL (^_Nullable interactiveTransitionGestureRecognizerTest)(CGPoint);
private var interactiveTransitionTestKey: UInt8 = 0

public extension UIView {
    var interactiveTransitionGestureRecognizerTest: ((CGPoint) -> Bool)? {
        get {
            return objc_getAssociatedObject(self, &interactiveTransitionTestKey) as? ((CGPoint) -> Bool)
        } set {
            objc_setAssociatedObject(self, &interactiveTransitionTestKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }
}
