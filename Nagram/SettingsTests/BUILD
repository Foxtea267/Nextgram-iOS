load("@build_bazel_rules_swift//swift:swift.bzl", "swift_test")

swift_test(
    name = "NextgramSettingsTests",
    srcs = glob(["*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = ["//Nagram/Settings:NagramSettings"],
)
