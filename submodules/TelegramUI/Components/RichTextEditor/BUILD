load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:resources.bzl", "apple_resource_bundle")
load("//build-system/bazel-utils:plist_fragment.bzl", "plist_fragment")

swift_library(
    name = "RichTextEditorCore",
    module_name = "RichTextEditorCore",
    srcs = glob([
        "Sources/RichTextEditorCore/**/*.swift",
    ]),
    visibility = [
        "//visibility:public",
    ],
)

plist_fragment(
    name = "RichTextEditorUIKitResourcesBundleInfoPlist",
    extension = "plist",
    template =
    """
    <key>CFBundleIdentifier</key>
    <string>org.telegram.RichTextEditorUIKitResources</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleName</key>
    <string>RichTextEditorUIKitResources</string>
    """
)

apple_resource_bundle(
    name = "RichTextEditorUIKitResources",
    infoplists = [
        ":RichTextEditorUIKitResourcesBundleInfoPlist",
    ],
    resources = glob([
        "Sources/RichTextEditorUIKit/Resources/Media.xcassets/**",
    ]),
)

swift_library(
    name = "RichTextEditorUIKit",
    module_name = "RichTextEditorUIKit",
    srcs = glob([
        "Sources/RichTextEditorUIKit/**/*.swift",
    ]),
    data = [
        ":RichTextEditorUIKitResources",
    ],
    deps = [
        ":RichTextEditorCore",
        "//submodules/AppBundle",
        "//submodules/MosaicLayout:MosaicLayout",
    ],
    visibility = [
        "//visibility:public",
    ],
)
