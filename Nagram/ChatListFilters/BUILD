load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: NEXTGRAM — 首页本地快捷筛选，不写入 Telegram 服务端文件夹。
swift_library(
    name = "NagramChatListFilters",
    module_name = "NagramChatListFilters",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
