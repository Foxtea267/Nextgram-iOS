load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: NAGRAM — 上下镜像的列表：用于「从下往上显示」，列表整体翻转，行与标题各自翻回来。
swift_library(
    name = "NagramFlippedList",
    module_name = "NagramFlippedList",
    srcs = glob(["Sources/**/*.swift"]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
    ],
    visibility = ["//visibility:public"],
)
