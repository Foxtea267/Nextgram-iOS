load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "NextgramTypography",
    module_name = "NextgramTypography",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = ["//Nagram/Settings:NagramSettings"],
    visibility = ["//visibility:public"],
)
