// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyCount",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "KeyCount",
            path: "Sources/KeyCount"
        )
    ]
)
