// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IndexPilot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "IndexPilot", targets: ["IndexPilot"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.27.0"),
    ],
    targets: [
        .target(
            name: "IndexPilot",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/IndexPilot",
            exclude: ["Info.plist"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "IndexPilotTests",
            dependencies: [
                "IndexPilot",
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/IndexPilotTests",
            resources: [
                .copy("../Fixtures"),
            ]
        ),
    ]
)