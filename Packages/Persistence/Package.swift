// swift-tools-version: 6.0
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "Persistence",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        .package(path: "../GeoKit"),
        .package(path: "../ImageMetadataKit")
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [
                .product(name: "GeoKit", package: "GeoKit"),
                .product(name: "ImageMetadataKit", package: "ImageMetadataKit")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
