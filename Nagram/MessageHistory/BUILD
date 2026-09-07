load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

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
    ],
    visibility = [
        "//visibility:public",
    ],
)
