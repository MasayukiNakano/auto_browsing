// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AutoBrowsingApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AutoBrowsingApp", targets: ["AutoBrowsingApp"])
    ],
    dependencies: [
        // Add third-party dependencies here when needed.
    ],
    targets: [
        .executableTarget(
            name: "AutoBrowsingApp",
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AutoBrowsingAppTests",
            dependencies: ["AutoBrowsingApp"],
            path: "Tests"
        )
    ]
)
