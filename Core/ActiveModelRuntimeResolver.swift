import Foundation

public enum ActiveModelRuntimeIssue: Equatable, Sendable {
    case invalidTier(packageID: String)
    case unsupportedTier(packageID: String, tier: ModelTier)
    case missingModelPath(packageID: String)
    case unverifiedModelPath(packageID: String)
    case unsafeModelPath(packageID: String)
    case modelFileMissing(packageID: String)
    case unsupportedConfiguration(packageID: String)
    case duplicateTier(ModelTier)
}

public struct ActiveModelRuntimeDescriptor: Equatable, Sendable {
    public let packageID: String
    public let tier: ModelTier
    public let modelURL: URL
    public let contextTokens: Int
    public let maximumOutputTokens: Int

    public init(
        packageID: String,
        tier: ModelTier,
        modelURL: URL,
        contextTokens: Int,
        maximumOutputTokens: Int
    ) {
        self.packageID = packageID
        self.tier = tier
        self.modelURL = modelURL
        self.contextTokens = contextTokens
        self.maximumOutputTokens = maximumOutputTokens
    }
}

public struct ActiveModelRuntimeResolution: Equatable, Sendable {
    public let descriptors: [ModelTier: ActiveModelRuntimeDescriptor]
    public let issues: [ActiveModelRuntimeIssue]

    public init(
        descriptors: [ModelTier: ActiveModelRuntimeDescriptor],
        issues: [ActiveModelRuntimeIssue]
    ) {
        self.descriptors = descriptors
        self.issues = issues
    }
}

/// Converts registry-approved model packs into runtime descriptors without
/// weakening the signed-manifest boundary. A metadata path is usable only when
/// it is safe, names a verified artifact, and matches the accepted Lite
/// configuration. Higher tiers remain disabled until separately evaluated.
public struct ActiveModelRuntimeResolver: Sendable {
    public static let acceptedLiteModelIdentity =
        "ggml-org/gemma-3-1b-it-GGUF@f9c28bcd85737ffc5aef028638d3341d49869c27"
    public static let acceptedRuntimeRelease = "b9637"

    public init() {}

    public func resolve(
        activePacks: ActivePackSnapshot
    ) -> ActiveModelRuntimeResolution {
        var descriptors: [ModelTier: ActiveModelRuntimeDescriptor] = [:]
        var blockedTiers: Set<ModelTier> = []
        var issues: [ActiveModelRuntimeIssue] = []

        for package in activePacks.models {
            let packageID = package.manifest.packageID
            guard let rawTier = package.manifest.metadata["model_tier"],
                  let tier = ModelTier(rawValue: rawTier),
                  tier != .essential else {
                issues.append(.invalidTier(packageID: packageID))
                continue
            }
            guard tier == .lite else {
                issues.append(.unsupportedTier(packageID: packageID, tier: tier))
                continue
            }
            guard let modelPath = package.manifest.metadata["model_path"],
                  !modelPath.isEmpty else {
                issues.append(.missingModelPath(packageID: packageID))
                continue
            }
            guard package.manifest.artifacts.contains(where: {
                $0.path == modelPath
            }) else {
                issues.append(.unverifiedModelPath(packageID: packageID))
                continue
            }

            let modelURL: URL
            do {
                modelURL = try PackageVerifier.safeArtifactURL(
                    path: modelPath,
                    root: package.directory
                )
            } catch {
                issues.append(.unsafeModelPath(packageID: packageID))
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: modelURL.path,
                isDirectory: &isDirectory
            ), !isDirectory.boolValue else {
                issues.append(.modelFileMissing(packageID: packageID))
                continue
            }

            guard package.manifest.metadata["model_identity"]
                    == Self.acceptedLiteModelIdentity,
                  package.manifest.metadata["model_family"] == "gemma3",
                  package.manifest.metadata["quantization"] == "Q4_K_M",
                  package.manifest.metadata["runtime_release"]
                    == Self.acceptedRuntimeRelease,
                  package.manifest.metadata["chat_template"] == "embedded",
                  package.manifest.metadata["context_tokens"]
                    == String(LlamaRuntimeConfiguration.liteContextTokens),
                  package.manifest.metadata["maximum_output_tokens"]
                    == String(LlamaRuntimeConfiguration.liteMaximumOutputTokens)
            else {
                issues.append(.unsupportedConfiguration(packageID: packageID))
                continue
            }

            guard descriptors[tier] == nil,
                  !blockedTiers.contains(tier) else {
                descriptors.removeValue(forKey: tier)
                blockedTiers.insert(tier)
                issues.append(.duplicateTier(tier))
                continue
            }
            descriptors[tier] = ActiveModelRuntimeDescriptor(
                packageID: packageID,
                tier: tier,
                modelURL: modelURL,
                contextTokens: LlamaRuntimeConfiguration.liteContextTokens,
                maximumOutputTokens: LlamaRuntimeConfiguration.liteMaximumOutputTokens
            )
        }

        return ActiveModelRuntimeResolution(
            descriptors: descriptors,
            issues: issues
        )
    }
}
