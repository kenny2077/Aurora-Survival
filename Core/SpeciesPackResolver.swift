import Foundation

public enum SpeciesPackIssue: Equatable, Sendable {
    case missingPackage
    case duplicatePackage
    case unsupportedContract(String)
    case unsafeArtifact(String)
    case missingArtifact(String)
}

public struct SpeciesPackDescriptor: Equatable, Sendable {
    public let packageID: String
    public let version: String
    public let modelIdentity: String
    public let encoderURL: URL
    public let speciesTableURL: URL
    public let embeddingsURL: URL
    public let encoderSHA256: String
    public let speciesCount: Int

    public init(
        packageID: String,
        version: String,
        modelIdentity: String,
        encoderURL: URL,
        speciesTableURL: URL,
        embeddingsURL: URL,
        encoderSHA256: String,
        speciesCount: Int
    ) {
        self.packageID = packageID
        self.version = version
        self.modelIdentity = modelIdentity
        self.encoderURL = encoderURL
        self.speciesTableURL = speciesTableURL
        self.embeddingsURL = embeddingsURL
        self.encoderSHA256 = encoderSHA256
        self.speciesCount = speciesCount
    }
}

public struct SpeciesPackResolution: Equatable, Sendable {
    public let descriptor: SpeciesPackDescriptor?
    public let issues: [SpeciesPackIssue]
}

public struct SpeciesPackResolver: Sendable {
    public static let contractVersion = "1"
    public static let inputSide = "224"
    public static let embeddingDimensions = "768"

    public init() {}

    public func resolve(activePacks: ActivePackSnapshot) -> SpeciesPackResolution {
        guard !activePacks.species.isEmpty else {
            return SpeciesPackResolution(descriptor: nil, issues: [.missingPackage])
        }
        guard activePacks.species.count == 1, let package = activePacks.species.first else {
            return SpeciesPackResolution(descriptor: nil, issues: [.duplicatePackage])
        }
        let metadata = package.manifest.metadata
        guard metadata["species_contract"] == Self.contractVersion,
              metadata["input_side"] == Self.inputSide,
              metadata["embedding_dimensions"] == Self.embeddingDimensions,
              metadata["softmax_temperature"] == "100",
              let modelIdentity = metadata["model_identity"], !modelIdentity.isEmpty,
              let encoderPath = metadata["encoder_path"],
              let tablePath = metadata["species_table_path"],
              let embeddingsPath = metadata["embeddings_path"],
              let digestPath = metadata["encoder_digest_artifact_path"],
              let speciesCount = Int(metadata["species_count"] ?? ""),
              speciesCount > 0,
              let digestArtifact = package.manifest.artifacts.first(where: {
                  $0.path == digestPath
              })
        else {
            return SpeciesPackResolution(
                descriptor: nil,
                issues: [.unsupportedContract(package.manifest.packageID)]
            )
        }
        guard let encoderURL = artifactURL(encoderPath, package: package),
              let tableURL = artifactURL(tablePath, package: package),
              let embeddingsURL = artifactURL(embeddingsPath, package: package)
        else {
            return SpeciesPackResolution(
                descriptor: nil,
                issues: [.unsafeArtifact(package.manifest.packageID)]
            )
        }
        guard FileManager.default.fileExists(atPath: encoderURL.path),
              FileManager.default.fileExists(atPath: tableURL.path),
              FileManager.default.fileExists(atPath: embeddingsURL.path)
        else {
            return SpeciesPackResolution(
                descriptor: nil,
                issues: [.missingArtifact(package.manifest.packageID)]
            )
        }
        return SpeciesPackResolution(
            descriptor: SpeciesPackDescriptor(
                packageID: package.manifest.packageID,
                version: package.manifest.version,
                modelIdentity: modelIdentity,
                encoderURL: encoderURL,
                speciesTableURL: tableURL,
                embeddingsURL: embeddingsURL,
                encoderSHA256: digestArtifact.sha256,
                speciesCount: speciesCount
            ),
            issues: []
        )
    }

    private func artifactURL(
        _ path: String,
        package: ResolvedActivePackage
    ) -> URL? {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains(".."),
              package.manifest.artifacts.contains(where: {
                  $0.path == path || $0.path.hasPrefix(path + "/")
              })
        else { return nil }
        let root = package.directory.standardizedFileURL
        let result = root.appendingPathComponent(path).standardizedFileURL
        guard result.path == root.path || result.path.hasPrefix(root.path + "/") else {
            return nil
        }
        return result
    }
}
