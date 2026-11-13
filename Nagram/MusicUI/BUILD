load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "NextgramMusicUI",
    module_name = "NextgramMusicUI",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//Nagram/Lyrics:NextgramLyrics",
        "//Nagram/Settings:NagramSettings",
        "//Nagram/SettingsSignal:NagramSettingsSignal",
        "//Nagram/Strings:NagramStrings",
        "//submodules/AccountContext:AccountContext",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/LegacyMediaPickerUI:LegacyMediaPickerUI",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
        "//submodules/PhotoResources:PhotoResources",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUI/Components/EdgeEffect:EdgeEffect",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
    ],
    visibility = ["//visibility:public"],
)
