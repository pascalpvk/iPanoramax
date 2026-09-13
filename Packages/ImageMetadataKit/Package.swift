// swift-tools-version: 6.0
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "ImageMetadataKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ImageMetadataKit", targets: ["ImageMetadataKit"])
    ],
    targets: [
        .target(
            name: "ImageMetadataKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ImageMetadataKitTests",
            dependencies: ["ImageMetadataKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
