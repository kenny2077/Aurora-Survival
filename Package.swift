// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AuroraCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AuroraCore", targets: ["AuroraCore"])
    ],
    targets: [
        .target(
            name: "AuroraCore",
            path: "Core"
        ),
        .testTarget(
            name: "AuroraCoreTests",
            dependencies: ["AuroraCore"],
            path: "Tests"
        )
    ]
)
