// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MediaTracker",
    platforms: [
        .macOS(.v14)
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
