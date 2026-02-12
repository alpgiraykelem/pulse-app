// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ActivityTracker",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.3.1"),
    ],
    targets: [
        .executableTarget(
            name: "ActivityTracker",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/ActivityTracker"
        ),
        .testTarget(
            name: "ActivityTrackerTests",
            dependencies: ["ActivityTracker"],
            path: "Tests/ActivityTrackerTests"
        ),
    ]
)
