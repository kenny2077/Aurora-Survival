// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AuroraCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AuroraCore", targets: ["AuroraCore"]),
        .executable(
            name: "trailguard-pack-check",
            targets: ["AuroraPackCheck"]
        )
    ],
    targets: [
        .target(
            name: "AuroraCore",
            path: "Core"
        ),
        .executableTarget(
            name: "AuroraPackCheck",
            dependencies: ["AuroraCore"],
            path: "tools/pack-check"
        ),
        .testTarget(
            name: "AuroraCoreTests",
            dependencies: ["AuroraCore"],
            path: "Tests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
