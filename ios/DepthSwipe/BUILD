load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Drop-in module: submodules/TelegramUI/Components/ChatList/DepthSwipe
# (next to the other chat list components, e.g. ChatList/ChatListHeaderNoticeComponent).
# ChatListUI depends on it; ChatListItemNode owns one DepthSwipeController per row.

swift_library(
    name = "DepthSwipe",
    module_name = "DepthSwipe",
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
