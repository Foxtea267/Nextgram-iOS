load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@rules_cc//cc:objc_library.bzl", "objc_library")

objc_library(
    name = "NextgramUpdateArchive",
    module_name = "NextgramUpdateArchive",
    enable_modules = True,
    srcs = ["UpdateArchive.m"],
    hdrs = ["UpdateArchive.h"],
    sdk_frameworks = ["Foundation"],
    deps = ["//third-party/ZipArchive:ZipArchive"],
)

swift_library(
    name = "NextgramUpdate",
    module_name = "NextgramUpdate",
    srcs = ["Release.swift", "ReleaseDownload.swift"],
    copts = ["-warnings-as-errors"],
    deps = [":NextgramUpdateArchive"],
    visibility = ["//Nagram/SettingsUI:__pkg__"],
)
