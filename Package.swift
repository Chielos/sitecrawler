// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IndexPilot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "IndexPilot", targets: ["IndexPilot"]),
    ],
    dependencies: [
        // HTML parsing — Swift port of Jsoup, the industry standard
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
        // SQLite ORM with migrations and typed queries
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.27.0"),
    ],
    targets: [
        .executableTarget(
            name: "IndexPilot",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/IndexPilot",
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
