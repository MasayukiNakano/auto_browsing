// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TextFieldSandbox",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "TextFieldSandbox",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
    ]
)
