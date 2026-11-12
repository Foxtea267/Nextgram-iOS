load("@build_bazel_rules_apple//apple:apple.bzl", "apple_dynamic_xcframework_import")

package(default_visibility = ["//visibility:public"])

apple_dynamic_xcframework_import(
    name = "Python",
    xcframework_imports = glob([
        "Python.xcframework/Info.plist",
        "Python.xcframework/*/Python.framework/**",
    ]),
)

filegroup(
    name = "stdlib",
    srcs = glob(
        ["Python.xcframework/lib/python3.11/**/*.py", "Python.xcframework/lib/python3.11/LICENSE*"],
        exclude = ["Python.xcframework/lib/python3.11/test/**", "Python.xcframework/lib/python3.11/ensurepip/**"],
    ),
)
