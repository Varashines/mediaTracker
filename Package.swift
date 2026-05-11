// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MediaTracker",
    platforms: [
        .macOS(.v26) // Now valid with tools-version 6.2
    ],
    products: [
        .executable(name: "MediaTracker", targets: ["MediaTracker"])
    ],
    targets: [
        .executableTarget(
            name: "MediaTracker",
            dependencies: [],
            path: "Sources/MediaTracker",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MediaTrackerTests",
            dependencies: ["MediaTracker"],
            path: "Tests/MediaTrackerTests"
        )
    ]
)
