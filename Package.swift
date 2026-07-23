// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TrailGuardCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TrailGuardCore", targets: ["TrailGuardCore"])
    ],
    targets: [
        .target(
            name: "TrailGuardCore",
            path: "Core"
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
