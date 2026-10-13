load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Drop-in module: submodules/TelegramUI/Components/Gifts/GlassGifts
# (same layout as its neighbours, e.g. submodules/TelegramUI/Components/Gifts/GiftItemComponent).

swift_library(
    name = "GlassGifts",
    module_name = "GlassGifts",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
    ],
    visibility = [
        "//visibility:public",
    ],
)
