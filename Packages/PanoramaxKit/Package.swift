// swift-tools-version: 6.0
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "PanoramaxKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PanoramaxKit", targets: ["PanoramaxKit"])
    ],
    targets: [
        .target(
            name: "PanoramaxKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PanoramaxKitTests",
            dependencies: ["PanoramaxKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
