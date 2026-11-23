load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "NextgramImageSuperResolution",
    module_name = "NextgramImageSuperResolution",
    srcs = glob(["Sources/*.swift"]),
    copts = ["-warnings-as-errors"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "ModelResources",
    srcs = glob(["Resources/*"]),
    visibility = ["//visibility:public"],
)
