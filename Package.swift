// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MediaTracker",
    platforms: [
        .macOS(.v15)
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
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-warn-long-expression-type-checking=100",
                    "-Xfrontend", "-warn-long-function-bodies=100"
                ])
            ]
        ),
        .testTarget(
            name: "MediaTrackerTests",
            dependencies: ["MediaTracker"],
            path: "Tests/MediaTrackerTests"
        )
    ]
)
