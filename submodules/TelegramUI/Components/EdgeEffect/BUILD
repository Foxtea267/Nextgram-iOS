load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "EdgeEffect",
    module_name = "EdgeEffect",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Nagram/Settings:NagramSettings", # MARK: NEXTGRAM
        "//Nagram/SettingsSignal:NagramSettingsSignal", # MARK: NEXTGRAM
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit", # MARK: NEXTGRAM
        "//submodules/Display",
        "//submodules/ComponentFlow",
        "//submodules/Components/ComponentDisplayAdapters",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
