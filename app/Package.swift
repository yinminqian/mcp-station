// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MCPMac",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "MCPMac",
            path: "Sources/MCPMac",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "MCPMacTests",
            dependencies: ["MCPMac"],
            path: "Tests/MCPMacTests"
        ),
    ]
)
