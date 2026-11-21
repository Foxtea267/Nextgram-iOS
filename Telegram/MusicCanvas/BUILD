load("@build_configuration//:variables.bzl", "telegram_bazel_path")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@rules_xcodeproj//xcodeproj:defs.bzl", "top_level_target", "xcodeproj")

swift_library(
    name = "MusicCanvasHost",
    srcs = [
        "MusicCanvasApp.swift",
        "MusicCanvasPreviews.swift",
    ],
    copts = ["-warnings-as-errors"],
    deps = ["//Nagram/MusicUI:NextgramMusicUI"],
)

# rules_xcodeproj merges this single Swift dependency into the application.
# The #Preview definitions must belong to the app, not the player's static library.
ios_application(
    name = "MusicCanvas",
    bundle_id = "app.nextgram.MusicCanvas",
    families = ["iphone"],
    minimum_os_version = "15.0",
    infoplists = ["Info.plist"],
    linkopts = ["-framework", "MediaPlayer"],
    resources = [
        "Resources/MusicCanvasARU.jpg",
        "//Telegram:AppStringResources",
        "//Telegram:GeneratedPresentationStrings/Resources/PresentationStrings.data",
    ],
    deps = [":MusicCanvasHost"],
    tags = ["manual"],
    visibility = ["//visibility:public"],
)

xcodeproj(
    name = "MusicCanvas_xcodeproj",
    bazel_path = telegram_bazel_path,
    project_name = "MusicCanvas",
    tags = ["manual"],
    top_level_targets = [
        top_level_target(":MusicCanvas", target_environments = ["simulator"]),
    ],
    focused_targets = [
        ":MusicCanvas",
        ":MusicCanvasHost",
        "//Nagram/MusicUI:NextgramMusicUI",
    ],
    xcode_configurations = {
        "Debug": {
            "//command_line_option:compilation_mode": "dbg",
        },
    },
    default_xcode_configuration = "Debug",
)
