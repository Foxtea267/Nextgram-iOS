load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@rules_cc//cc:objc_library.bzl", "objc_library")

exports_files(["PythonIOS.BUILD"])

genrule(
    name = "python_stdlib",
    srcs = ["@nextgram_python_ios//:stdlib"],
    outs = ["NextgramPython311.zip"],
    cmd = "/usr/bin/python3 $(location package_stdlib.py) $@ $(SRCS)",
    tools = ["package_stdlib.py"],
)

objc_library(
    name = "NagramExteraPythonAPI",
    hdrs = ["Python/ExteraPython.h"],
    enable_modules = True,
    module_name = "NagramExteraPythonAPI",
)

objc_library(
    name = "NagramExteraPython",
    srcs = ["Python/ExteraPython.m"],
    alwayslink = True,
    deps = [
        ":NagramExteraPythonAPI",
        "@nextgram_python_ios//:Python",
    ],
    visibility = ["//Telegram:__pkg__"],
)

filegroup(
    name = "ExteraRuntimeResources",
    srcs = [":python_stdlib", "Resources/NextgramExteraRuntime.py"],
    visibility = ["//Telegram:__pkg__"],
)

swift_library(
    name = "NagramPlugins",
    module_name = "NagramPlugins",
    srcs = glob(["Sources/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [":NagramExteraPythonAPI"],
    visibility = [
        "//Nagram/SettingsUI:__pkg__",
        "//submodules/TelegramUI:__pkg__",
    ],
)
