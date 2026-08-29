// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WebSmoke",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "WebSmoke", targets: ["WebSmoke"]),
    ],
    dependencies: [
        .package(path: "../../MarkdownKit"),
    ],
    targets: [
        .executableTarget(
            name: "WebSmoke",
            dependencies: ["MarkdownKit"]
        ),
    ]
)
