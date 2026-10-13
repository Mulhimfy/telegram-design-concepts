// swift-tools-version: 5.9
// The Living Icons' motion and artwork (pure Swift: Foundation + CoreGraphics), replayed against golden
// frames recorded from the web prototype (tools/golden-icons.mjs). Run: swift test
import PackageDescription

let package = Package(
    name: "LivingIconsCore",
    platforms: [.macOS(.v13), .iOS(.v15)],
    targets: [
        // CI copies ios/LivingSettingsIcons/Sources/LivingIcon*.swift here (single source of truth).
        .target(name: "LivingIconsCore", path: "Sources/LivingIconsCore"),
        .testTarget(
            name: "LivingIconsCoreTests",
            dependencies: ["LivingIconsCore"],
            path: "Tests/LivingIconsCoreTests",
            resources: [.copy("Resources/golden-icons.json"), .copy("Resources/telegram-glyphs.json")]
        ),
    ]
)
