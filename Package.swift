// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "E2BBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "E2BBar", targets: ["E2BBar"])
    ],
    targets: [
        .executableTarget(
            name: "E2BBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
