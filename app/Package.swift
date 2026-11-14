// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MCPStation",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS("26.0")],
    dependencies: [
        // 自动更新（和 paster 同一套）：读仓库里的 appcast.xml，从 GitHub Release 下载 EdDSA 签过名的 DMG
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "MCPStation",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/MCPStation",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "MCPStationTests",
            dependencies: ["MCPStation"],
            path: "Tests/MCPStationTests"
        ),
    ]
)
