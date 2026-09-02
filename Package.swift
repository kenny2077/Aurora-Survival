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
            name: "aurora-pack-check",
            targets: ["AuroraPackCheck"]
        )
    ],
    targets: [
        .target(
            name: "AuroraCore",
            path: "Core",
            swiftSettings: [
                .define("AURORA_MESH_BETA", .when(configuration: .debug))
            ]
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
            ],
            swiftSettings: [
                .define("AURORA_MESH_BETA", .when(configuration: .debug))
            ]
        )
    ]
)
