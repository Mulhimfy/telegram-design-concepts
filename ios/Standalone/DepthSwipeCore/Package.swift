// swift-tools-version: 5.9
// The Depth Swipe maths alone (pure Swift): the rig, its springs and the row-side driving, replayed
// against golden frames recorded from the web prototype (tools/golden-depth.mjs). Run: swift test
import PackageDescription

let package = Package(
    name: "DepthSwipeCore",
    platforms: [.macOS(.v13), .iOS(.v15)],
    targets: [
        // CI copies ios/DepthSwipe/Sources/DepthSwipe{Spring,Rig,Tracker}.swift here (single source of truth).
        .target(name: "DepthSwipeCore", path: "Sources/DepthSwipeCore"),
        .testTarget(
            name: "DepthSwipeCoreTests",
            dependencies: ["DepthSwipeCore"],
            path: "Tests/DepthSwipeCoreTests",
            resources: [.copy("Resources/golden-depth.json")]
        ),
    ]
)
