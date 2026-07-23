import Foundation

public struct VehicleDocumentManifest: Codable, Equatable, Sendable {
    public let documentID: String
    public let revision: String
    public let vehicle: VehicleProfile
    public let articleIDs: [String]
    public let licenseIdentifier: String

    public init(
        documentID: String,
        revision: String,
        vehicle: VehicleProfile,
        articleIDs: [String],
        licenseIdentifier: String
    ) {
        self.documentID = documentID
        self.revision = revision
        self.vehicle = vehicle
        self.articleIDs = articleIDs
        self.licenseIdentifier = licenseIdentifier
    }
}

public enum VehicleDocumentIngestionError: Error, Equatable {
    case invalidManifest
    case missingArticle(String)
    case unreviewedArticle(String)
    case applicabilityMismatch(String)
    case sourceRevisionMismatch(String)
}

public struct VehicleDocumentIngestor: Sendable {
    public init() {}

    public func validate(
        manifest: VehicleDocumentManifest,
        articles: [KnowledgeArticle]
    ) throws {
        guard !manifest.documentID.isEmpty,
              !manifest.revision.isEmpty,
              !manifest.licenseIdentifier.isEmpty,
              manifest.vehicle.isPlausible,
              !manifest.articleIDs.isEmpty,
              Set(manifest.articleIDs).count == manifest.articleIDs.count
        else {
            throw VehicleDocumentIngestionError.invalidManifest
        }

        let byID = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
        for articleID in manifest.articleIDs {
            guard let article = byID[articleID] else {
                throw VehicleDocumentIngestionError.missingArticle(articleID)
            }
            guard article.reviewed else {
                throw VehicleDocumentIngestionError.unreviewedArticle(articleID)
            }
            guard article.source.id == manifest.documentID,
                  article.source.revision == manifest.revision
            else {
                throw VehicleDocumentIngestionError.sourceRevisionMismatch(
                    articleID
                )
            }
            guard manifest.vehicle.documentID?.caseInsensitiveCompare(
                manifest.documentID
            ) == .orderedSame,
                  article.vehicleApplicability?.matches(
                      manifest.vehicle
                  ) == true else {
                throw VehicleDocumentIngestionError.applicabilityMismatch(
                    articleID
                )
            }
        }
    }
}
