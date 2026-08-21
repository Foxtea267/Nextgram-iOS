// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RichTextEditor",
    platforms: [.iOS(.v13), .macOS(. v10_13)],
    products: [
        .library(name: "RichTextEditorCore", targets: ["RichTextEditorCore"]),
        .library(name: "RichTextEditorUIKit", targets: ["RichTextEditorUIKit"]),
    ],
    dependencies: [
        .package(path: "../../../MosaicLayout"),
    ],
    targets: [
        .target(name: "RichTextEditorCore"),
        .testTarget(name: "RichTextEditorCoreTests", dependencies: ["RichTextEditorCore"]),
        .target(name: "RichTextEditorUIKit", dependencies: [
            "RichTextEditorCore",
            .product(name: "MosaicLayout", package: "MosaicLayout"),
        ], resources: [.process("Resources/Media.xcassets")]),
        .testTarget(name: "RichTextEditorUIKitTests", dependencies: ["RichTextEditorUIKit"]),
    ]
)
