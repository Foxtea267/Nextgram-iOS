load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "NextgramVoiceMessages",
    module_name = "NextgramVoiceMessages",
    srcs = glob(["Sources/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = ["//submodules/FFMpegBinding", "//submodules/OpusBinding"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "ChatVoiceImport",
    srcs = glob(["TelegramUI/*.swift"]),
    visibility = ["//submodules/TelegramUI:__pkg__"],
)
