// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MarkdownKit",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "MarkdownKit", targets: ["MarkdownKit"]),
    ],
    targets: [
        // Web assets are copied verbatim so the JS/CSS directory structure is
        // preserved inside MarkdownKit_MarkdownKit.bundle.
        .target(
            name: "MarkdownKit",
            resources: [
                .copy("Resources"),
            ]
        ),
    ]
)
