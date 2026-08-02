import Foundation

public enum OfflineMapResolutionIssue: Equatable, Sendable {
    case missingManifest(packageID: String)
    case invalidManifest(packageID: String)
    case identityMismatch(packageID: String)
    case unsafeArtifactPath(packageID: String)
    case notReady(packageID: String, issues: [MapReadinessIssue])
}

public struct ResolvedOfflineMap: Equatable, Sendable, Identifiable {
    public var id: String { pack.id }
    public let pack: OfflineMapPack
    public let packageDirectory: URL
    public let pmtilesURL: URL
    public let styleURL: URL
    public let glyphsDirectoryURL: URL?
    public let attribution: String
    public let session: OfflineMapSession

    public init(
        pack: OfflineMapPack,
        packageDirectory: URL,
        pmtilesURL: URL,
        styleURL: URL,
        glyphsDirectoryURL: URL?,
        attribution: String,
        session: OfflineMapSession
    ) {
        self.pack = pack
        self.packageDirectory = packageDirectory
        self.pmtilesURL = pmtilesURL
        self.styleURL = styleURL
        self.glyphsDirectoryURL = glyphsDirectoryURL
        self.attribution = attribution
        self.session = session
    }
}

public struct OfflineMapResolution: Equatable, Sendable {
    public let maps: [ResolvedOfflineMap]
    public let issues: [OfflineMapResolutionIssue]

    public init(
        maps: [ResolvedOfflineMap],
        issues: [OfflineMapResolutionIssue]
    ) {
        self.maps = maps
        self.issues = issues
    }
}

/// Converts only already-verified active map packages into local rendering
/// descriptors. Every referenced path is resolved under its package directory;
/// no URL from package metadata can escape the signed package boundary.
public struct OfflineMapRuntimeResolver: Sendable {
    private let runtime: FileBackedOfflineMapRuntime

    public init(runtime: FileBackedOfflineMapRuntime = .init()) {
        self.runtime = runtime
    }

    public func resolve(activePacks: ActivePackSnapshot) -> OfflineMapResolution {
        var maps: [ResolvedOfflineMap] = []
        var issues: [OfflineMapResolutionIssue] = []

        for package in activePacks.maps {
            let packageID = package.manifest.packageID
            let manifestPath = package.manifest.metadata["map_manifest_path"]
                ?? "map.json"
            let manifestURL: URL
            do {
                manifestURL = try PackageVerifier.safeArtifactURL(
                    path: manifestPath,
                    root: package.directory
                )
            } catch {
                issues.append(.unsafeArtifactPath(packageID: packageID))
                continue
            }
            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                issues.append(.missingManifest(packageID: packageID))
                continue
            }

            let map: OfflineMapPack
            do {
                map = try JSONDecoder().decode(
                    OfflineMapPack.self,
                    from: Data(contentsOf: manifestURL)
                )
            } catch {
                issues.append(.invalidManifest(packageID: packageID))
                continue
            }
            guard map.id == packageID,
                  map.version == package.manifest.version
            else {
                issues.append(.identityMismatch(packageID: packageID))
                continue
            }

            let pmtilesURL: URL
            let styleURL: URL
            let glyphsDirectoryURL: URL?
            do {
                pmtilesURL = try PackageVerifier.safeArtifactURL(
                    path: map.pmtilesPath,
                    root: package.directory
                )
                styleURL = try PackageVerifier.safeArtifactURL(
                    path: map.stylePath,
                    root: package.directory
                )
                glyphsDirectoryURL = try map.glyphsDirectoryPath.map {
                    try PackageVerifier.safeArtifactURL(
                        path: $0,
                        root: package.directory
                    )
                }
            } catch {
                issues.append(.unsafeArtifactPath(packageID: packageID))
                continue
            }

            do {
                let session = try runtime.open(
                    pack: map,
                    packageDirectory: package.directory,
                    tripCoordinate: nil,
                    requiredTier: .scout,
                    requiresOfflineRouting: false
                )
                maps.append(
                    ResolvedOfflineMap(
                        pack: map,
                        packageDirectory: package.directory,
                        pmtilesURL: pmtilesURL,
                        styleURL: styleURL,
                        glyphsDirectoryURL: glyphsDirectoryURL,
                        attribution: package.manifest.metadata["attribution"]
                            ?? "© OpenStreetMap contributors",
                        session: session
                    )
                )
            } catch let OfflineMapRuntimeError.notReady(readinessIssues) {
                issues.append(
                    .notReady(
                        packageID: packageID,
                        issues: readinessIssues
                    )
                )
            } catch {
                issues.append(.invalidManifest(packageID: packageID))
            }
        }

        return OfflineMapResolution(
            maps: maps.sorted { $0.pack.name < $1.pack.name },
            issues: issues
        )
    }
}
