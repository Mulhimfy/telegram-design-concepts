// swift-tools-version: 5.9
// The interaction model alone (pure Swift), replayed against golden trajectories
// recorded from the web prototype (tools/golden.mjs). Run: swift test
import PackageDescription

let package = Package(
    name: "GlassCoinCore",
    platforms: [.macOS(.v13), .iOS(.v15)],
    targets: [
        // CI copies ios/GlassCoinAvatar/Sources/GlassCoinPhysics.swift here (single source of truth).
        .target(name: "GlassCoinCore", path: "Sources/GlassCoinCore"),
        .testTarget(
            name: "GlassCoinCoreTests",
            dependencies: ["GlassCoinCore"],
            path: "Tests/GlassCoinCoreTests",
            resources: [.copy("Resources/golden.json")]
        ),
    ]
)
