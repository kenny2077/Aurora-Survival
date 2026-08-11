// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AuroraLlamaRuntime",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "AuroraLlamaRuntime",
            targets: ["AuroraLlamaRuntime"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b9637/llama-b9637-xcframework.zip",
            checksum: "46c7dad871f804d82399ddcfeb54d23b6469888801fc35124d7e33e543a9bef7"
        ),
        .target(
            name: "AuroraLlamaC",
            dependencies: ["llama"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
            ]
        ),
        .target(
            name: "AuroraLlamaRuntime",
            dependencies: ["AuroraLlamaC"]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
