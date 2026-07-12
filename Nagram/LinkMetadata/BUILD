load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "NagramLinkMetadata",
    module_name = "NagramLinkMetadata",
    srcs = glob(["Sources/**/*.swift"]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = ["//visibility:public"],
)
