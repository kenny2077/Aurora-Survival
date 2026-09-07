import Foundation

public protocol PackageEnvelopeVerifying: Sendable {
    func verify(
        envelope: SignedPackageEnvelope,
        packageDirectory: URL
    ) throws
}

extension PackageVerifier: PackageEnvelopeVerifying {}

public enum ActivePackIssue: Equatable, Sendable {
    case invalidActivationIndex
    case missingInstalledRecord(packageID: String, version: String)
    case recalled(packageID: String, version: String)
    case unsafePackageDirectory(packageID: String)
    case missingEnvelope(packageID: String)
    case invalidEnvelope(packageID: String)
    case identityMismatch(packageID: String)
    case verificationFailed(packageID: String)
    case incompatibleAppVersion(packageID: String, minimum: String)
    case policyMismatch(packageID: String)
    case entitlementMissing(packageID: String, productID: String)
    case unapprovedKnowledge(packageID: String)
    case invalidModelTier(packageID: String)
    case deviceIneligible(packageID: String, tier: ModelTier)
}

public struct ResolvedActivePackage: Equatable, Sendable, Identifiable {
    public var id: String { "\(manifest.packageID)@\(manifest.version)" }
    public let manifest: PackageManifest
    public let directory: URL

    public init(manifest: PackageManifest, directory: URL) {
        self.manifest = manifest
        self.directory = directory
    }
}

public struct ActivePackSnapshot: Equatable, Sendable {
    public let models: [ResolvedActivePackage]
    public let knowledge: [ResolvedActivePackage]
    public let maps: [ResolvedActivePackage]
    public let species: [ResolvedActivePackage]
    public let installedTiers: Set<ModelTier>
    public let issues: [ActivePackIssue]

    public init(
        models: [ResolvedActivePackage],
        knowledge: [ResolvedActivePackage],
        maps: [ResolvedActivePackage],
        species: [ResolvedActivePackage] = [],
        installedTiers: Set<ModelTier>,
        issues: [ActivePackIssue]
    ) {
        self.models = models
        self.knowledge = knowledge
        self.maps = maps
        self.species = species
        self.installedTiers = installedTiers
        self.issues = issues
    }

    public static let noModels = ActivePackSnapshot(
        models: [],
        knowledge: [],
        maps: [],
        species: [],
        installedTiers: [],
        issues: []
    )
}

/// Re-verifies the active package set at launch. A package is exposed to the
/// runtime only after its activation record, signature/hash envelope,
/// entitlement, policy version, app version, review state, recall state, and
/// device gate all agree. A failure leaves Ask unavailable unless Lite remains.
public actor ActivePackRegistry {
    private let rootDirectory: URL
    private let verifier: any PackageEnvelopeVerifying
    private let appVersion: String
    private let expectedPolicyVersion: String
    private let allowDevelopmentKnowledge: Bool
    private let allowDevelopmentExpert: Bool
    private let fileManager: FileManager
    private let router: ModelRouter

    public init(
        rootDirectory: URL,
        verifier: any PackageEnvelopeVerifying,
        appVersion: String,
        expectedPolicyVersion: String,
        allowDevelopmentKnowledge: Bool = false,
        allowDevelopmentExpert: Bool = false,
        fileManager: FileManager = .default,
        router: ModelRouter = ModelRouter()
    ) {
        self.rootDirectory = rootDirectory
        self.verifier = verifier
        self.appVersion = appVersion
        self.expectedPolicyVersion = expectedPolicyVersion
        self.allowDevelopmentKnowledge = allowDevelopmentKnowledge
        self.allowDevelopmentExpert = allowDevelopmentExpert
        self.fileManager = fileManager
        self.router = router
    }

    public func resolve(
        cachedEntitlements: [EntitlementSnapshot],
        device: DeviceSnapshot
    ) -> ActivePackSnapshot {
        let index: PackageActivationIndex
        do {
            index = try readIndex()
        } catch {
            return ActivePackSnapshot(
                models: [],
                knowledge: [],
                maps: [],
                installedTiers: [],
                issues: [.invalidActivationIndex]
            )
        }

        var models: [ResolvedActivePackage] = []
        var knowledge: [ResolvedActivePackage] = []
        var maps: [ResolvedActivePackage] = []
        var species: [ResolvedActivePackage] = []
        var installedTiers: Set<ModelTier> = []
        var issues: [ActivePackIssue] = []

        for packageID in index.activeVersions.keys.sorted() {
            guard let version = index.activeVersions[packageID] else { continue }
            guard let record = index.installed.first(where: {
                $0.packageID == packageID && $0.version == version
            }) else {
                issues.append(
                    .missingInstalledRecord(
                        packageID: packageID,
                        version: version
                    )
                )
                continue
            }
            if (index.recalledVersions[packageID] ?? []).contains(version) {
                issues.append(.recalled(packageID: packageID, version: version))
                continue
            }

            let packageDirectory: URL
            do {
                packageDirectory = try PackageVerifier.safeArtifactURL(
                    path: record.directoryName,
                    root: packagesDirectory
                )
            } catch {
                issues.append(.unsafePackageDirectory(packageID: packageID))
                continue
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: packageDirectory.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                issues.append(.unsafePackageDirectory(packageID: packageID))
                continue
            }

            let envelopeURL = packageDirectory.appendingPathComponent(
                "envelope.json",
                isDirectory: false
            )
            guard fileManager.fileExists(atPath: envelopeURL.path) else {
                issues.append(.missingEnvelope(packageID: packageID))
                continue
            }

            let envelope: SignedPackageEnvelope
            do {
                envelope = try JSONDecoder().decode(
                    SignedPackageEnvelope.self,
                    from: Data(contentsOf: envelopeURL)
                )
            } catch {
                issues.append(.invalidEnvelope(packageID: packageID))
                continue
            }

            let manifest = envelope.manifest
            guard manifest.packageID == record.packageID,
                  manifest.version == record.version,
                  manifest.kind == record.kind
            else {
                issues.append(.identityMismatch(packageID: packageID))
                continue
            }

            do {
                try verifier.verify(
                    envelope: envelope,
                    packageDirectory: packageDirectory
                )
            } catch {
                issues.append(.verificationFailed(packageID: packageID))
                continue
            }

            guard Self.version(appVersion, isAtLeast: manifest.minimumAppVersion) else {
                issues.append(
                    .incompatibleAppVersion(
                        packageID: packageID,
                        minimum: manifest.minimumAppVersion
                    )
                )
                continue
            }

            if let packagePolicy = manifest.metadata["policy_version"],
               packagePolicy != expectedPolicyVersion {
                issues.append(.policyMismatch(packageID: packageID))
                continue
            }

            let productID = manifest.metadata["product_id"]
            guard OfflineEntitlementResolver().canLaunch(
                productID: productID,
                packageIsInstalled: true,
                cachedEntitlements: cachedEntitlements
            ) else {
                issues.append(
                    .entitlementMissing(
                        packageID: packageID,
                        productID: productID ?? ""
                    )
                )
                continue
            }

            let resolved = ResolvedActivePackage(
                manifest: manifest,
                directory: packageDirectory
            )
            switch manifest.kind {
            case .model:
                guard let rawTier = manifest.metadata["model_tier"],
                      let tier = ModelTier(rawValue: rawTier)
                else {
                    issues.append(.invalidModelTier(packageID: packageID))
                    continue
                }
                let route = router.route(
                    requested: tier,
                    installed: [tier],
                    expertValidated: tier == .expert
                        ? allowDevelopmentExpert
                        : false,
                    device: device
                )
                guard route.selected == tier else {
                    issues.append(
                        .deviceIneligible(packageID: packageID, tier: tier)
                    )
                    continue
                }
                models.append(resolved)
                installedTiers.insert(tier)

            case .knowledge:
                let reviewStatus = manifest.metadata["review_status"]
                guard reviewStatus == "approved"
                        || (allowDevelopmentKnowledge
                            && reviewStatus == "development_fixture")
                else {
                    issues.append(.unapprovedKnowledge(packageID: packageID))
                    continue
                }
                knowledge.append(resolved)

            case .map:
                maps.append(resolved)

            case .species:
                species.append(resolved)
            }
        }

        return ActivePackSnapshot(
            models: models.sorted { $0.id < $1.id },
            knowledge: knowledge.sorted { $0.id < $1.id },
            maps: maps.sorted { $0.id < $1.id },
            species: species.sorted { $0.id < $1.id },
            installedTiers: installedTiers,
            issues: issues
        )
    }

    private var packagesDirectory: URL {
        rootDirectory.appendingPathComponent("packages", isDirectory: true)
    }

    private func readIndex() throws -> PackageActivationIndex {
        let url = rootDirectory.appendingPathComponent(
            "activation-index.json",
            isDirectory: false
        )
        guard fileManager.fileExists(atPath: url.path) else {
            return PackageActivationIndex()
        }
        return try JSONDecoder().decode(
            PackageActivationIndex.self,
            from: Data(contentsOf: url)
        )
    }

    private static func version(
        _ candidate: String,
        isAtLeast minimum: String
    ) -> Bool {
        guard let candidateParts = versionParts(candidate),
              let minimumParts = versionParts(minimum)
        else { return false }
        let count = max(candidateParts.count, minimumParts.count)
        for index in 0..<count {
            let left = index < candidateParts.count ? candidateParts[index] : 0
            let right = index < minimumParts.count ? minimumParts[index] : 0
            if left != right {
                return left > right
            }
        }
        return true
    }

    private static func versionParts(_ value: String) -> [Int]? {
        let numeric = value.split(separator: "-", maxSplits: 1).first ?? ""
        let parts = numeric.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        let integers = parts.compactMap { Int($0) }
        return integers.count == parts.count ? integers : nil
    }
}
