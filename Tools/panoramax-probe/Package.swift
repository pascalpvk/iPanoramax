// swift-tools-version: 6.0
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "panoramax-probe",
    platforms: [.macOS(.v14)],
    products: [
        // Le produit porte le tiret, la cible non : un nom de module Swift ne
        // peut pas contenir de tiret.
        .executable(name: "panoramax-probe", targets: ["PanoramaxProbe"])
    ],
    dependencies: [
        .package(path: "../../Packages/PanoramaxKit")
    ],
    targets: [
        .executableTarget(
            name: "PanoramaxProbe",
            dependencies: [
                .product(name: "PanoramaxKit", package: "PanoramaxKit")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
