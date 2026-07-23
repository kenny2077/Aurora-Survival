import Foundation

public struct EmergencyCoreBundle: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let version: String
    public let policyVersion: String
    public let articles: [KnowledgeArticle]

    public init(
        schemaVersion: Int = 1,
        version: String,
        policyVersion: String,
        articles: [KnowledgeArticle]
    ) {
        self.schemaVersion = schemaVersion
        self.version = version
        self.policyVersion = policyVersion
        self.articles = articles
    }
}

public enum EmergencyCoreOrigin: Equatable, Sendable {
    case active
    case bundledFirstLaunch
    case bundledRecovery
}

public struct EmergencyCoreLoadResult: Equatable, Sendable {
    public let bundle: EmergencyCoreBundle
    public let origin: EmergencyCoreOrigin
}

public enum EmergencyCoreError: Error, Equatable {
    case bundledCoreInvalid
    case fileOperationFailed
}

public struct EmergencyCoreStore {
    private let rootDirectory: URL
    private let bundledData: Data
    private let fileManager: FileManager

    public init(
        rootDirectory: URL,
        bundledData: Data,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.bundledData = bundledData
        self.fileManager = fileManager
    }

    public func loadOrRecover() throws -> EmergencyCoreLoadResult {
        guard let bundled = try? Self.decodeAndValidate(bundledData) else {
            throw EmergencyCoreError.bundledCoreInvalid
        }
        let activeURL = rootDirectory.appendingPathComponent("emergency-core.json")
        do {
            try fileManager.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: activeURL.path) {
                if let active = try? Self.decodeAndValidate(Data(contentsOf: activeURL)) {
                    return EmergencyCoreLoadResult(bundle: active, origin: .active)
                }
                try bundledData.write(to: activeURL, options: [.atomic])
                return EmergencyCoreLoadResult(bundle: bundled, origin: .bundledRecovery)
            }
            try bundledData.write(to: activeURL, options: [.atomic])
            return EmergencyCoreLoadResult(bundle: bundled, origin: .bundledFirstLaunch)
        } catch let error as EmergencyCoreError {
            throw error
        } catch {
            throw EmergencyCoreError.fileOperationFailed
        }
    }

    private static func decodeAndValidate(_ data: Data) throws -> EmergencyCoreBundle {
        let bundle = try JSONDecoder().decode(EmergencyCoreBundle.self, from: data)
        guard bundle.schemaVersion == 1,
              !bundle.version.isEmpty,
              !bundle.policyVersion.isEmpty,
              !bundle.articles.isEmpty,
              bundle.articles.allSatisfy(\.reviewed)
        else {
            throw EmergencyCoreError.bundledCoreInvalid
        }
        return bundle
    }
}
