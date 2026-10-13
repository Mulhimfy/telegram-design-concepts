// swift-tools-version: 5.9
// The glass gifts' model alone (pure Swift: GlassTileModel, GlassGiftMotionFilter), replayed against golden frames
// recorded from the web prototype (tools/golden-gifts.mjs). Run: swift test
import PackageDescription

let package = Package(
    name: "GlassGiftsCore",
    platforms: [.macOS(.v13), .iOS(.v15)],
    targets: [
        // CI copies ios/GlassGifts/Sources/GlassTileModel.swift and GlassGiftMotionFilter.swift here (the module is
        // the single source of truth; see .gitignore).
        .target(name: "GlassGiftsCore", path: "Sources/GlassGiftsCore"),
        .testTarget(
            name: "GlassGiftsCoreTests",
            dependencies: ["GlassGiftsCore"],
            path: "Tests/GlassGiftsCoreTests",
            resources: [.copy("Resources/golden-gifts.json")]
        ),
    ]
)
