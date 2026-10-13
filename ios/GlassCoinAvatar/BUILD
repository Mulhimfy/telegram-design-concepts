load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load(
    "@build_bazel_rules_apple//apple:resources.bzl",
    "apple_resource_bundle",
)
load(
    "//build-system/bazel-utils:plist_fragment.bzl",
    "plist_fragment",
)

# Drop-in module: submodules/TelegramUI/Components/PeerInfo/GlassCoinAvatar
# (same layout as submodules/TelegramUI/Components/LiquidGlassShapes).

filegroup(
    name = "GlassCoinAvatarMetalSources",
    srcs = glob([
        "Metal/**/*.metal",
    ]),
    visibility = ["//visibility:public"],
)

plist_fragment(
    name = "GlassCoinAvatarMetalSourcesBundleInfoPlist",
    extension = "plist",
    template =
    """
    <key>CFBundleIdentifier</key>
    <string>org.telegram.GlassCoinAvatarMetalSources</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleName</key>
    <string>GlassCoinAvatar</string>
    """
)

apple_resource_bundle(
    name = "GlassCoinAvatarMetalSourcesBundle",
    infoplists = [
        ":GlassCoinAvatarMetalSourcesBundleInfoPlist",
    ],
    resources = [
        ":GlassCoinAvatarMetalSources",
    ],
)

swift_library(
    name = "GlassCoinAvatar",
    module_name = "GlassCoinAvatar",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    data = [
        ":GlassCoinAvatarMetalSourcesBundle",
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/UIKitRuntimeUtils:UIKitRuntimeUtils",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/MetalEngine",
    ],
    visibility = [
        "//visibility:public",
    ],
)
