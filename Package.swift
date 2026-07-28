// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TrailGuardCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TrailGuardCore", targets: ["TrailGuardCore"]),
        .executable(
            name: "trailguard-pack-check",
            targets: ["TrailGuardPackCheck"]
        )
    ],
    targets: [
        .target(
            name: "TrailGuardCore",
            path: "Core"
        ),
        .executableTarget(
            name: "TrailGuardPackCheck",
            dependencies: ["TrailGuardCore"],
            path: "tools/pack-check"
        ),
        .testTarget(
            name: "TrailGuardCoreTests",
            dependencies: ["TrailGuardCore"],
            path: "Tests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
