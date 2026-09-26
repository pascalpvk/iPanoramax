// swift-tools-version: 6.0
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "GeoKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GeoKit", targets: ["GeoKit"])
    ],
    dependencies: [
        .package(path: "../ImageMetadataKit")
    ],
    targets: [
        .target(
            name: "GeoKit",
            dependencies: [
                .product(name: "ImageMetadataKit", package: "ImageMetadataKit")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "GeoKitTests",
            dependencies: ["GeoKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
