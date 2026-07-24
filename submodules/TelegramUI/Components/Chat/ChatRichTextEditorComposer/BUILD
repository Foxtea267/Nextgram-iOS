load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatRichTextEditorComposer",
    module_name = "ChatRichTextEditorComposer",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AppBundle",
        "//submodules/AsyncDisplayKit",
        "//submodules/ContextUI",
        "//submodules/Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/TextFormat",
        "//submodules/TelegramUI/Components/RichTextEditor:RichTextEditorCore",
        "//submodules/TelegramUI/Components/RichTextEditor:RichTextEditorUIKit",
        "//submodules/TelegramUI/Components/Chat/ChatInputTextNode",
        "//submodules/TelegramUI/Components/PlainButtonComponent",
        "//submodules/Components/BundleIconComponent",
        "//submodules/Components/MultilineTextComponent",
        "//submodules/CheckNode",
        "//submodules/Pasteboard",
    ],
    visibility = [
        "//visibility:public",
    ],
)
