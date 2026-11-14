// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MCPStation",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "MCPStation",
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
