import Foundation

public enum ActiveModelRuntimeIssue: Equatable, Sendable {
    case invalidTier(packageID: String)
    case unsupportedTier(packageID: String, tier: ModelTier)
    case missingModelPath(packageID: String)
    case unverifiedModelPath(packageID: String)
    case unsafeModelPath(packageID: String)
    case modelFileMissing(packageID: String)
    case missingProjectorPath(packageID: String)
    case unverifiedProjectorPath(packageID: String)
    case unsafeProjectorPath(packageID: String)
    case projectorFileMissing(packageID: String)
    case missingEmbeddingModelPath(packageID: String)
    case unverifiedEmbeddingModelPath(packageID: String)
    case unsafeEmbeddingModelPath(packageID: String)
    case embeddingModelFileMissing(packageID: String)
    case unsupportedConfiguration(packageID: String)
    case duplicateTier(ModelTier)
}

public enum ExpertMemoryProfileStatus: String, Equatable, Sendable {
    case calibration
    case retained
}

public struct ActiveModelRuntimeDescriptor: Equatable, Sendable {
    public let packageID: String
    public let tier: ModelTier
    public let modelURL: URL
    public let visionProjectorURL: URL?
    public let embeddingModelURL: URL?
    public let contextTokens: Int
    public let maximumOutputTokens: Int
    public let expertMemoryProfile: ExpertRuntimeMemoryProfile?
    public let expertMemoryProfileStatus: ExpertMemoryProfileStatus?

    public init(
        packageID: String,
        tier: ModelTier,
        modelURL: URL,
        visionProjectorURL: URL? = nil,
        embeddingModelURL: URL? = nil,
        contextTokens: Int,
        maximumOutputTokens: Int,
        expertMemoryProfile: ExpertRuntimeMemoryProfile? = nil,
        expertMemoryProfileStatus: ExpertMemoryProfileStatus? = nil
    ) {
        self.packageID = packageID
        self.tier = tier
        self.modelURL = modelURL
        self.visionProjectorURL = visionProjectorURL
        self.embeddingModelURL = embeddingModelURL
        self.contextTokens = contextTokens
        self.maximumOutputTokens = maximumOutputTokens
        self.expertMemoryProfile = expertMemoryProfile
        self.expertMemoryProfileStatus = expertMemoryProfileStatus
    }
}

public struct ActiveModelRuntimeResolution: Equatable, Sendable {
    public let descriptors: [ModelTier: ActiveModelRuntimeDescriptor]
    public let calibrationExpertDescriptor: ActiveModelRuntimeDescriptor?
    public let issues: [ActiveModelRuntimeIssue]

    public init(
        descriptors: [ModelTier: ActiveModelRuntimeDescriptor],
        calibrationExpertDescriptor: ActiveModelRuntimeDescriptor? = nil,
        issues: [ActiveModelRuntimeIssue]
    ) {
        self.descriptors = descriptors
        self.calibrationExpertDescriptor = calibrationExpertDescriptor
        self.issues = issues
    }
}

/// Converts registry-approved model packs into exact runtime descriptors. The
/// Expert allowlist is development-only until physical acceptance is retained.
public struct ActiveModelRuntimeResolver: Sendable {
    public static let acceptedLiteModelIdentity =
        "ggml-org/gemma-3-1b-it-GGUF@f9c28bcd85737ffc5aef028638d3341d49869c27"
    public static let acceptedExpertModelIdentity =
        "Qwen/Qwen3-VL-2B-Instruct-GGUF@52d6c8ffea26cc873ac5ad116f8631268d7eb503"
    public static let acceptedExpertProjectorIdentity =
        "Qwen/Qwen3-VL-2B-Instruct-GGUF@52d6c8ffea26cc873ac5ad116f8631268d7eb503:mmproj-Q8_0"
    public static let acceptedExpertEmbeddingIdentity =
        "BAAI/bge-small-en-v1.5@5c38ec7c405ec4b44b94cc5a9bb96e735b38267a"
    public static let acceptedExpertEmbeddingDimensions = 384
    public static let acceptedExpertEmbeddingContextTokens = 512
    public static let acceptedExpertModelBytes: Int64 = 1_107_409_952
    public static let acceptedExpertModelSHA256 =
        "089d75c52f4b7ffc56ba998ffc50aae89fcafc755f9e7208aacca281dca6c2ae"
    public static let acceptedExpertProjectorBytes: Int64 = 445_053_216
    public static let acceptedExpertProjectorSHA256 =
        "f9a68fabba69c3b81e153367b2c7521030b0fa8bb0de400c9599c8e6725f9c82"
    public static let acceptedRuntimeRelease = "b9637"
    public static let acceptedRuntimeCommit =
        "aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3"


    private let allowDevelopmentExpert: Bool

    public init(allowDevelopmentExpert: Bool = false) {
        self.allowDevelopmentExpert = allowDevelopmentExpert
    }

    public func resolve(
        activePacks: ActivePackSnapshot
    ) -> ActiveModelRuntimeResolution {
        var descriptors: [ModelTier: ActiveModelRuntimeDescriptor] = [:]
        var blockedTiers: Set<ModelTier> = []
        var calibrationExpertDescriptor: ActiveModelRuntimeDescriptor?
        var issues: [ActiveModelRuntimeIssue] = []

        for package in activePacks.models {
            let packageID = package.manifest.packageID
            guard let rawTier = package.manifest.metadata["model_tier"],
                  let tier = ModelTier(rawValue: rawTier) else {
                issues.append(.invalidTier(packageID: packageID))
                continue
            }
            guard tier == .lite || allowDevelopmentExpert else {
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
            guard let modelURL = safeExistingArtifact(
                path: modelPath,
                package: package,
                unsafeIssue: .unsafeModelPath(packageID: packageID),
                missingIssue: .modelFileMissing(packageID: packageID),
                issues: &issues
            ) else { continue }

            let descriptor: ActiveModelRuntimeDescriptor?
            switch tier {
            case .lite:
                descriptor = liteDescriptor(
                    packageID: packageID,
                    modelURL: modelURL,
                    metadata: package.manifest.metadata,
                    issues: &issues
                )
            case .expert:
                descriptor = expertDescriptor(
                    packageID: packageID,
                    modelURL: modelURL,
                    package: package,
                    issues: &issues
                )
            }
            guard let descriptor else { continue }

            if descriptor.expertMemoryProfileStatus == .calibration {
                guard calibrationExpertDescriptor == nil else {
                    calibrationExpertDescriptor = nil
                    issues.append(.duplicateTier(.expert))
                    continue
                }
                calibrationExpertDescriptor = descriptor
                continue
            }

            guard descriptors[tier] == nil,
                  !blockedTiers.contains(tier) else {
                descriptors.removeValue(forKey: tier)
                blockedTiers.insert(tier)
                issues.append(.duplicateTier(tier))
                continue
            }
            descriptors[tier] = descriptor
        }

        return ActiveModelRuntimeResolution(
            descriptors: descriptors,
            calibrationExpertDescriptor: calibrationExpertDescriptor,
            issues: issues
        )
    }

    private func liteDescriptor(
        packageID: String,
        modelURL: URL,
        metadata: [String: String],
        issues: inout [ActiveModelRuntimeIssue]
    ) -> ActiveModelRuntimeDescriptor? {
        guard metadata["model_identity"] == Self.acceptedLiteModelIdentity,
              metadata["model_family"] == "gemma3",
              metadata["quantization"] == "Q4_K_M",
              metadata["runtime_release"] == Self.acceptedRuntimeRelease,
              metadata["chat_template"] == "embedded",
              metadata["context_tokens"]
                == String(LlamaRuntimeConfiguration.liteContextTokens),
              metadata["maximum_output_tokens"]
                == String(LlamaRuntimeConfiguration.liteMaximumOutputTokens)
        else {
            issues.append(.unsupportedConfiguration(packageID: packageID))
            return nil
        }
        return ActiveModelRuntimeDescriptor(
            packageID: packageID,
            tier: .lite,
            modelURL: modelURL,
            contextTokens: LlamaRuntimeConfiguration.liteContextTokens,
            maximumOutputTokens: LlamaRuntimeConfiguration.liteMaximumOutputTokens
        )
    }

    private func expertDescriptor(
        packageID: String,
        modelURL: URL,
        package: ResolvedActivePackage,
        issues: inout [ActiveModelRuntimeIssue]
    ) -> ActiveModelRuntimeDescriptor? {
        let metadata = package.manifest.metadata
        guard let modelPath = metadata["model_path"],
              let modelArtifact = package.manifest.artifacts.first(where: {
                $0.path == modelPath
              }),
              modelArtifact.byteCount == Self.acceptedExpertModelBytes,
              modelArtifact.sha256 == Self.acceptedExpertModelSHA256
        else {
            issues.append(.unsupportedConfiguration(packageID: packageID))
            return nil
        }
        guard metadata["model_identity"] == Self.acceptedExpertModelIdentity,
              metadata["model_family"] == "qwen3vl",
              metadata["quantization"] == "Q4_K_M",
              metadata["vision_projector_identity"]
                == Self.acceptedExpertProjectorIdentity,
              metadata["vision_projector_quantization"] == "Q8_0",
              metadata["runtime_release"] == Self.acceptedRuntimeRelease,
              metadata["runtime_commit"] == Self.acceptedRuntimeCommit,
              metadata["chat_template"] == "embedded",
              metadata["context_tokens"] == "8192",
              metadata["maximum_output_tokens"] == "256",
              let profileStatus = ExpertMemoryProfileStatus(
                rawValue: metadata["memory_profile_status"] ?? ""
              )
        else {
            issues.append(.unsupportedConfiguration(packageID: packageID))
            return nil
        }
        guard let projectorPath = metadata["vision_projector_path"],
              !projectorPath.isEmpty else {
            issues.append(.missingProjectorPath(packageID: packageID))
            return nil
        }
        guard package.manifest.artifacts.contains(where: {
            $0.path == projectorPath
        }) else {
            issues.append(.unverifiedProjectorPath(packageID: packageID))
            return nil
        }
        guard let projectorArtifact = package.manifest.artifacts.first(where: {
            $0.path == projectorPath
        }),
              projectorArtifact.byteCount == Self.acceptedExpertProjectorBytes,
              projectorArtifact.sha256 == Self.acceptedExpertProjectorSHA256
        else {
            issues.append(.unsupportedConfiguration(packageID: packageID))
            return nil
        }
        guard let projectorURL = safeExistingArtifact(
            path: projectorPath,
            package: package,
            unsafeIssue: .unsafeProjectorPath(packageID: packageID),
            missingIssue: .projectorFileMissing(packageID: packageID),
            issues: &issues
        ) else { return nil }

        guard let embeddingPath = metadata["embedding_model_path"],
              !embeddingPath.isEmpty else {
            issues.append(.missingEmbeddingModelPath(packageID: packageID))
            return nil
        }
        guard let embeddingArtifact = package.manifest.artifacts.first(where: {
            $0.path == embeddingPath
        }) else {
            issues.append(.unverifiedEmbeddingModelPath(packageID: packageID))
            return nil
        }
        guard metadata["embedding_model_identity"]
                == Self.acceptedExpertEmbeddingIdentity,
              metadata["embedding_quantization"] == "Q8_0",
              metadata["embedding_dimensions"]
                == String(Self.acceptedExpertEmbeddingDimensions),
              metadata["embedding_context_tokens"]
                == String(Self.acceptedExpertEmbeddingContextTokens),
              metadata["embedding_artifact_bytes"]
                == String(embeddingArtifact.byteCount),
              metadata["embedding_artifact_sha256"]
                == embeddingArtifact.sha256,
              metadata["vector_index_schema"] == "3",
              metadata["knowledge_index_schema"] == "3",
              metadata["corpus_package_schema"] == "3"
        else {
            issues.append(.unsupportedConfiguration(packageID: packageID))
            return nil
        }
        guard let embeddingURL = safeExistingArtifact(
            path: embeddingPath,
            package: package,
            unsafeIssue: .unsafeEmbeddingModelPath(packageID: packageID),
            missingIssue: .embeddingModelFileMissing(packageID: packageID),
            issues: &issues
        ) else { return nil }

        let memoryProfile: ExpertRuntimeMemoryProfile?
        switch profileStatus {
        case .calibration:
            guard metadata["peak_memory_full_bytes"] == nil,
                  metadata["peak_memory_balanced_bytes"] == nil,
                  metadata["peak_memory_constrained_bytes"] == nil
            else {
                issues.append(.unsupportedConfiguration(packageID: packageID))
                return nil
            }
            memoryProfile = nil
        case .retained:
            guard let fullPeak = Self.memoryValue(
                metadata["peak_memory_full_bytes"]
            ),
                  let balancedPeak = Self.memoryValue(
                    metadata["peak_memory_balanced_bytes"]
                  ),
                  let constrainedPeak = Self.memoryValue(
                    metadata["peak_memory_constrained_bytes"]
                  )
            else {
                issues.append(.unsupportedConfiguration(packageID: packageID))
                return nil
            }
            memoryProfile = ExpertRuntimeMemoryProfile(measuredPeakBytes: [
                .full: fullPeak,
                .balanced: balancedPeak,
                .constrained: constrainedPeak,
            ])
        }

        return ActiveModelRuntimeDescriptor(
            packageID: packageID,
            tier: .expert,
            modelURL: modelURL,
            visionProjectorURL: projectorURL,
            embeddingModelURL: embeddingURL,
            contextTokens: ExpertContextProfile.full.contextTokens,
            maximumOutputTokens: ExpertContextAssembler.outputTokenReserve,
            expertMemoryProfile: memoryProfile,
            expertMemoryProfileStatus: profileStatus
        )
    }

    private func safeExistingArtifact(
        path: String,
        package: ResolvedActivePackage,
        unsafeIssue: ActiveModelRuntimeIssue,
        missingIssue: ActiveModelRuntimeIssue,
        issues: inout [ActiveModelRuntimeIssue]
    ) -> URL? {
        let url: URL
        do {
            url = try PackageVerifier.safeArtifactURL(
                path: path,
                root: package.directory
            )
        } catch {
            issues.append(unsafeIssue)
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            issues.append(missingIssue)
            return nil
        }
        return url
    }

    private static func memoryValue(_ raw: String?) -> UInt64? {
        guard let raw, let value = UInt64(raw), value > 0 else { return nil }
        return value
    }
}
