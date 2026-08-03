// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TourBoxMicro",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TourBoxCore", targets: ["TourBoxCore"]),
        .executable(name: "TourBoxMicro", targets: ["TourBoxMicro"])
    ],
    dependencies: [
        .package(url: "https://github.com/markiv/SwiftUI-Shimmer", from: "1.5.1"),
        .package(url: "https://github.com/EmergeTools/Pow", from: "1.0.6")
    ],
    targets: [
        .target(
            name: "TourBoxCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "TourBoxMicro",
            dependencies: [
                "TourBoxCore",
                .product(name: "Shimmer", package: "SwiftUI-Shimmer"),
                .product(name: "Pow", package: "Pow")
            ]
        ),
        .testTarget(
            name: "TourBoxCoreTests",
            dependencies: ["TourBoxCore"]
        )
    ]
)
