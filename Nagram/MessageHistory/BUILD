load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# MARK: NEXTGRAM — 本地消息保留标记与编辑历史，不依赖 TelegramCore。
swift_library(
    name = "NagramMessageHistory",
    module_name = "NagramMessageHistory",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Postbox:Postbox",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_test(
    name = "NagramMessageHistoryTests",
    srcs = glob(["Tests/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        ":NagramMessageHistory",
        "//submodules/Postbox:Postbox",
    ],
)

filegroup(
    name = "CoreCapture",
    srcs = glob(["Core/*.swift"]),
    visibility = ["//submodules/TelegramCore:__pkg__"],
)
