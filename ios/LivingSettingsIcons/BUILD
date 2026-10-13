load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Drop-in module: submodules/TelegramUI/Components/PeerInfo/LivingSettingsIcons
# (Settings icons that come alive when you come back from their page; prototype/src/settings/living-icons.js).

swift_library(
    name = "LivingSettingsIcons",
    module_name = "LivingSettingsIcons",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/AppBundle",
    ],
    visibility = [
        "//visibility:public",
    ],
)
