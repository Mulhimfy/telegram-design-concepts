// swift-tools-version: 5.9
// Typechecks ios/DepthSwipe/Sources (the Telegram-facing code) for iOS against stubs whose
// declarations are copied from Telegram-iOS @ f1dd7a2 (Display: TextNode, SimpleLayer,
// SharedDisplayLinkDriver, ContainedViewLayoutTransition, UIScreenScale; AsyncDisplayKit:
// ASDisplayNode), and the ChatListItemNode hooks against the module (HookCheck: the patch's hook
// functions, verbatim, on stand-ins for the row's members). It proves the module's own code is
// well-typed against those APIs; the full proof is building it inside Telegram-iOS (ios/patches).
// Build: swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" --triple arm64-apple-ios15.0-simulator
import PackageDescription

let package = Package(
    name: "DepthSwipeTypeCheck",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "DepthSwipe", targets: ["DepthSwipe"]),
        .library(name: "DepthSwipeHookCheck", targets: ["DepthSwipeHookCheck"]),
    ],
    targets: [
        .target(name: "AsyncDisplayKit", path: "Stubs/AsyncDisplayKit"),
        .target(name: "Display", dependencies: ["AsyncDisplayKit"], path: "Stubs/Display"),
        // CI copies ios/DepthSwipe/Sources/*.swift here (single source of truth).
        .target(
            name: "DepthSwipe",
            dependencies: ["AsyncDisplayKit", "Display"],
            path: "Sources/DepthSwipe"
        ),
        .target(
            name: "DepthSwipeHookCheck",
            dependencies: ["AsyncDisplayKit", "Display", "DepthSwipe"],
            path: "HookCheck"
        ),
    ]
)
