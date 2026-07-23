import Foundation

public enum KnowledgeStoreError: Error {
    case missingResource
    case invalidData(Error)
}

public struct KnowledgeStore: Sendable {
    public let articles: [KnowledgeArticle]

    public init(articles: [KnowledgeArticle]) {
        self.articles = articles
    }

    public static func decode(data: Data) throws -> KnowledgeStore {
        do {
            let articles = try JSONDecoder().decode([KnowledgeArticle].self, from: data)
            return KnowledgeStore(articles: articles)
        } catch {
            throw KnowledgeStoreError.invalidData(error)
        }
    }

    public static func load(url: URL) throws -> KnowledgeStore {
        try decode(data: Data(contentsOf: url))
    }
}
