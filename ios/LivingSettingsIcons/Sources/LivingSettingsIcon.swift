import Foundation
import UIKit
import Display
import AppBundle

/// A Settings row whose icon comes alive when you come back from its page (prototype/src/ui/settings-screen.js
/// `defaultSettingsSections`, prototype/src/settings/living-icons.js `RIGS`). The raw value is the prototype's
/// icon name.
public enum LivingSettingsIcon: String, CaseIterable {
    case myProfile = "ic-profile"
    case money = "money"
    case proxy = "ic-proxy"
    case savedMessages = "ic-saved"
    case recentCalls = "ic-phone"
    case devices = "ic-devices"
    case chatFolders = "ic-folder"
    case notifications = "ic-bell"
    case privacy = "ic-lock"
    case dataAndStorage = "ic-data"
    case appearance = "ic-appearance"
    case powerSaving = "ic-power"
    case language = "ic-language"
    case premium = "ic-premium"
    case stars = "ic-stars"
    case business = "ic-business"
    case gift = "ic-gift"
    case support = "ic-ask"
    case faq = "ic-faq"
    case tips = "ic-features"
    /// The profile's own rows (accent glyphs, no tile).
    case emojiStatus = "set-emoji-status"
    case profileColor = "set-covercolor"
    case profilePhoto = "set-avatar"

    /// The motion (living-icons.js `RIGS[name]`).
    public var rig: LivingIconRig {
        return LivingIconRigs.all[self.rawValue]!
    }

    /// The tile behind the glyph as Telegram draws it, or nil where the glyph stands alone (the profile's
    /// own rows) or the row shows an image of its own (Money).
    public var tile: LivingSettingsIconTile? {
        // PresentationResourcesSettings.swift:109-117 (the palette) and :120-319 (each row's icon).
        let red: UInt32 = 0xFF453A
        let green: UInt32 = 0x34C759
        let blue: UInt32 = 0x0079ff
        let lightBlue: UInt32 = 0x32ADE6
        let orange: UInt32 = 0xFF9F0A
        let purple: UInt32 = 0xAF52DE
        let gray: UInt32 = 0x8E8E93
        switch self {
        case .myProfile:
            return .settings([red])
        case .proxy:
            return .settings([green])
        case .savedMessages:
            return .settings([blue])
        case .recentCalls:
            return .settings([green])
        case .devices:
            return .settings([orange])
        case .chatFolders:
            return .settings([lightBlue])
        case .notifications:
            return .settings([red])
        case .privacy:
            return .settings([gray])
        case .dataAndStorage:
            return .settings([green])
        case .appearance:
            return .settings([lightBlue])
        case .powerSaving:
            return .settings([orange])
        case .language:
            return .settings([purple])
        case .business:
            return .settings([0xA95CE3, 0xF16B80])
        case .support:
            return .settings([orange])
        case .faq:
            return .settings([lightBlue])
        case .tips:
            return .settings([0xffcc02])
        case .premium:
            // `PresentationResourcesSettings.premium`: 5 stops, bottom-left → top-right.
            return .custom([0x6b93ff, 0x6b93ff, 0x8d77ff, 0xb56eec, 0xb56eec], locations: [0.0, 0.15, 0.5, 0.85, 1.0])
        case .stars:
            return .custom([0xfec80f, 0xdd6f12], locations: [0.0, 1.0])
        case .gift:
            // `PresentationResourcesSettings.premiumGift`.
            return .custom([0x3ba1f2, 0x3ba1f2, 0x39b3b4, 0x34c27d, 0x34c27d], locations: [0.0, 0.15, 0.5, 0.85, 1.0])
        case .money, .emojiStatus, .profileColor, .profilePhoto:
            return nil
        }
    }
}

/// A Settings icon's tile: 30 × 30, corner 8, a gradient, Telegram's "Gradient" sheen (plus-lighter) and
/// "Backdrop" texture (overlay) — exactly `renderSettingsIcon(name:backgroundColors:)` or the custom
/// Premium / Stars / Gift tiles of PresentationResourcesSettings.swift, without the glyph.
public struct LivingSettingsIconTile {
    public enum Gradient {
        /// `renderSettingsIcon`: device RGB, from (w, h) to (0, 0) of its y-up context — the top-right corner (the
        /// first colour) to the bottom-left.
        case settings
        /// The custom tiles: `deviceColorSpace`, from (0, 0) to (w, h) — the bottom-left corner (the first stop) to
        /// the top-right — with locations.
        case custom(locations: [CGFloat])
    }

    public let colors: [UInt32]
    public let gradient: Gradient

    public static func settings(_ colors: [UInt32]) -> LivingSettingsIconTile {
        return LivingSettingsIconTile(colors: colors, gradient: .settings)
    }

    public static func custom(_ colors: [UInt32], locations: [CGFloat]) -> LivingSettingsIconTile {
        return LivingSettingsIconTile(colors: colors, gradient: .custom(locations: locations))
    }

    /// The tile's colour, for the effects drawn in it (living-icons.js `tileColor`: the first colour).
    public var color: UIColor {
        return UIColor(livingIconRGB: self.colors[0])
    }

    private static let gradientImage = UIImage(bundleImageName: "Item List/Icons/Gradient")
    private static let backdropImage = UIImage(bundleImageName: "Item List/Icons/Backdrop")
    private static var cache: [String: UIImage] = [:]

    /// The tile without its glyph, drawn once per palette (main thread).
    public func image() -> UIImage? {
        let key: String
        switch self.gradient {
        case .settings:
            key = "s" + self.colors.map { String($0, radix: 16) }.joined(separator: ",")
        case let .custom(locations):
            key = "c" + self.colors.map { String($0, radix: 16) }.joined(separator: ",") + locations.map { "\($0)" }.joined(separator: ",")
        }
        if let image = LivingSettingsIconTile.cache[key] {
            return image
        }
        let colors = self.colors
        let gradient = self.gradient
        let image = generateImage(CGSize(width: 30.0, height: 30.0), contextGenerator: { size, context in
            // PresentationResourcesSettings.swift:8-60 (renderSettingsIcon) and :174-217 (premium), minus the glyph.
            let bounds = CGRect(origin: CGPoint(), size: size)
            context.clear(bounds)

            let cgColors: [CGColor] = colors.map { UIColor(livingIconRGB: $0).cgColor }
            switch gradient {
            case .settings:
                var locations: [CGFloat] = [0.0, 1.0]
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let cgGradient = CGGradient(colorsSpace: colorSpace, colors: cgColors as CFArray, locations: &locations) {
                    context.drawLinearGradient(cgGradient, start: CGPoint(x: size.width, y: size.height), end: CGPoint(x: 0.0, y: 0.0), options: CGGradientDrawingOptions())
                }
            case let .custom(stops):
                var locations = stops
                if let cgGradient = CGGradient(colorsSpace: deviceColorSpace, colors: cgColors as CFArray, locations: &locations) {
                    context.drawLinearGradient(cgGradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: size.width, y: size.height), options: CGGradientDrawingOptions())
                }
            }

            if let gradientImage = LivingSettingsIconTile.gradientImage, let cgImage = gradientImage.cgImage {
                context.setBlendMode(.plusLighter)
                context.draw(cgImage, in: CGRect(origin: .zero, size: size))
            }

            if let backdropImage = LivingSettingsIconTile.backdropImage, let cgImage = backdropImage.cgImage {
                context.setBlendMode(.overlay)
                context.draw(cgImage, in: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size))
            }

            context.setBlendMode(.normal)

            let outerPath = UIBezierPath(rect: CGRect(origin: .zero, size: size))
            let innerPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8.0)
            outerPath.append(innerPath)

            context.saveGState()
            outerPath.usesEvenOddFillRule = true
            context.addPath(outerPath.cgPath)
            context.clip(using: .evenOdd)

            context.setBlendMode(.clear)
            context.fill(CGRect(origin: .zero, size: size))
            context.restoreGState()
        })
        if let image = image {
            LivingSettingsIconTile.cache[key] = image
        }
        return image
    }

    /// The tile's outline (`UIBezierPath(roundedRect:cornerRadius: 8)`), which clips what moves in it.
    public static let outline: CGPath = UIBezierPath(roundedRect: CGRect(x: 0.0, y: 0.0, width: 30.0, height: 30.0), cornerRadius: 8.0).cgPath
}

extension UIColor {
    convenience init(livingIconRGB rgb: UInt32, alpha: CGFloat = 1.0) {
        self.init(red: CGFloat((rgb >> 16) & 0xff) / 255.0, green: CGFloat((rgb >> 8) & 0xff) / 255.0, blue: CGFloat(rgb & 0xff) / 255.0, alpha: alpha)
    }
}
