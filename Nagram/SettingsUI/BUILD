load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: NAGRAM — Nagram 增强设置页 UI 层（ItemListController toggle）。
# 依赖数据层 Nagram/Settings + 上游 UI 模块；rebase 时上游碰不到 Nagram/。
swift_library(
    name = "NagramSettingsUI",
    module_name = "NagramSettingsUI",
    srcs = glob([
        "**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Display:Display",
        "//submodules/AvatarNode:AvatarNode",
        "//submodules/PhotoResources:PhotoResources",
        "//submodules/WallpaperBackgroundNode:WallpaperBackgroundNode",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/ItemListPeerItem:ItemListPeerItem",
        "//submodules/LegacyMediaPickerUI:LegacyMediaPickerUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AccountContext:AccountContext",
        "//submodules/PhoneNumberFormat:PhoneNumberFormat",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TextFormat:TextFormat",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/UndoUI:UndoUI",
        "//Nagram/Settings:NagramSettings",
        "//Nagram/Typography:NextgramTypography",
        "//Nagram/Plugins:NagramPlugins",
        "//Nagram/MessageHistory:NagramMessageHistory",
        "//Nagram/SessionBackupUI:NagramSessionBackupUI",
        "//Nagram/LinkMetadata:NagramLinkMetadata",
        "//Nagram/Strings:NagramStrings",
        "//Nagram/Update:NextgramUpdate",
        "//Nagram/SettingsSignal:NagramSettingsSignal",
        "//Nagram/Translate:NagramTranslate",
        "//Nagram/Transcription:NagramTranscription",
        # MARK: NAGRAM — 贴纸尺寸滑杆(SliderComponent,复刻省电模式粗轨道)
        "//submodules/AsyncDisplayKit",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/EdgeEffect",
        "//submodules/TelegramUI/Components/FaceScanScreen",
        "//submodules/TelegramUI/Components/SliderComponent",
        "//submodules/TelegramUI/Components/TabBarComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
