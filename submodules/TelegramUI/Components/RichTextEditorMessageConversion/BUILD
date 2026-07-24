load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "RichTextEditorMessageConversion",
    module_name = "RichTextEditorMessageConversion",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/TelegramCore",
        "//submodules/TextFormat",
        "//submodules/TelegramUI/Components/RichTextEditor:RichTextEditorCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
