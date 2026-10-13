// swift-tools-version: 5.9
// Typechecks ios/GlassGifts/Sources (the Telegram-facing module) for iOS against stubs whose declarations are copied
// from Telegram-iOS @ f1dd7a2 (Display, AsyncDisplayKit), and the patch's hooks (HookCheck) against the module. It
// proves the module's own code is well-typed against those APIs; the full proof is building it inside Telegram-iOS
// (ios/patches/0005-glass-gifts.patch).
// Build: swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" --triple arm64-apple-ios15.0-simulator
import PackageDescription

let package = Package(
    name: "GlassGiftsTypeCheck",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "GlassGifts", targets: ["GlassGifts"]),
    ],
    targets: [
        .target(name: "AsyncDisplayKit", path: "Stubs/AsyncDisplayKit"),
        .target(name: "Display", path: "Stubs/Display"),
        // CI copies ios/GlassGifts/Sources/*.swift here (the module is the single source of truth; see .gitignore).
        .target(name: "GlassGifts", dependencies: ["AsyncDisplayKit", "Display"], path: "Sources/GlassGifts"),
        .target(name: "GlassGiftsHookCheck", dependencies: ["AsyncDisplayKit", "Display", "GlassGifts"], path: "HookCheck"),
    ]
)
