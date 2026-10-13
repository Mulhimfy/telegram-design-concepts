// swift-tools-version: 5.9
// Typechecks ios/LivingSettingsIcons/Sources (the Telegram-facing module) for iOS against stubs whose
// declarations are copied from Telegram-iOS @ f1dd7a2 (AsyncDisplayKit, Display, AppBundle). It proves the
// module's own code is well-typed against those APIs; the full proof is building it inside Telegram-iOS
// (ios/patches/0003-living-icons.patch).
// Build: swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" --triple arm64-apple-ios15.0-simulator
import PackageDescription

let package = Package(
    name: "LivingIconsTypeCheck",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "LivingSettingsIcons", targets: ["LivingSettingsIcons"]),
    ],
    targets: [
        .target(name: "AsyncDisplayKit", path: "Stubs/AsyncDisplayKit"),
        .target(name: "AppBundle", path: "Stubs/AppBundle"),
        .target(name: "Display", dependencies: ["AsyncDisplayKit"], path: "Stubs/Display"),
        // CI copies ios/LivingSettingsIcons/Sources/*.swift here.
        .target(
            name: "LivingSettingsIcons",
            dependencies: ["AsyncDisplayKit", "Display", "AppBundle"],
            path: "Sources/LivingSettingsIcons"
        ),
    ]
)
