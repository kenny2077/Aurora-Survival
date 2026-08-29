// swift-tools-version: 5.9
import PackageDescription
import Foundation

let localRuntimePath = "Artifacts/llama.xcframework"
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let hasLocalRuntime = FileManager.default.fileExists(
    atPath: packageRoot.appendingPathComponent(localRuntimePath).path
)
let llamaTarget: Target = hasLocalRuntime ? .binaryTarget(
    name: "llama",
    path: localRuntimePath
) : .binaryTarget(
    name: "llama",
    url: "https://github.com/ggml-org/llama.cpp/releases/download/b9637/llama-b9637-xcframework.zip",
    checksum: "46c7dad871f804d82399ddcfeb54d23b6469888801fc35124d7e33e543a9bef7"
)
var llamaCXXSettings: [CXXSetting] = [.headerSearchPath("include")]
if hasLocalRuntime {
    llamaCXXSettings.append(.define("AURORA_LINKED_MTMD", .when(platforms: [.iOS])))
}

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
        llamaTarget,
        .target(
            name: "AuroraLlamaC",
            dependencies: ["llama"],
            publicHeadersPath: "include",
            cxxSettings: llamaCXXSettings,
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
