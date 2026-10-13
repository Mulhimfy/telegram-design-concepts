// swift-tools-version: 5.9
// Typechecks ios/GlassCoinAvatar/Sources (the Telegram-facing code) for iOS against stubs whose
// declarations are copied from Telegram-iOS @ f1dd7a2 (Display, MetalEngine, SwiftSignalKit,
// AsyncDisplayKit, UIKitRuntimeUtils). It proves the module's own code is well-typed against those
// APIs; the full proof is building it inside Telegram-iOS (ios/patches).
// Build: xcodebuild -scheme GlassCoinAvatar -destination 'generic/platform=iOS Simulator' build
import PackageDescription

let package = Package(
    name: "GlassCoinTypeCheck",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "GlassCoinAvatar", targets: ["GlassCoinAvatar"]),
    ],
    targets: [
        .target(name: "AsyncDisplayKit", path: "Stubs/AsyncDisplayKit"),
        .target(name: "SwiftSignalKit", path: "Stubs/SwiftSignalKit"),
        .target(name: "UIKitRuntimeUtils", path: "Stubs/UIKitRuntimeUtils"),
        .target(name: "Display", dependencies: ["AsyncDisplayKit", "SwiftSignalKit"], path: "Stubs/Display"),
        .target(name: "MetalEngine", dependencies: ["Display"], path: "Stubs/MetalEngine"),
        // CI copies ios/GlassCoinAvatar/Sources/*.swift here.
        .target(
            name: "GlassCoinAvatar",
            dependencies: ["AsyncDisplayKit", "Display", "UIKitRuntimeUtils", "SwiftSignalKit", "MetalEngine"],
            path: "Sources/GlassCoinAvatar"
        ),
    ]
)
