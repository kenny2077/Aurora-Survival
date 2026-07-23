import Foundation

public struct RetrievalEngine: Sendable {
    private let articles: [KnowledgeArticle]

    public init(articles: [KnowledgeArticle]) {
        self.articles = articles.filter(\.reviewed)
    }

    public func search(
        query: String,
        domain: KnowledgeDomain? = nil,
        limit: Int = 4
    ) -> [RetrievedPassage] {
        let queryTokens = Self.tokens(in: query)
        guard !queryTokens.isEmpty else { return [] }

        return articles
            .filter { domain == nil || $0.domain == domain }
            .compactMap { article -> RetrievedPassage? in
                let titleTokens = Self.tokens(in: article.title)
                let bodyTokens = Self.tokens(in: article.searchableText)
                let keywordTokens = Set(article.keywords.flatMap(Self.tokens))

                let titleHits = queryTokens.intersection(titleTokens).count
                let bodyHits = queryTokens.intersection(bodyTokens).count
                let keywordHits = queryTokens.intersection(keywordTokens).count
                let phraseBonus = article.searchableText
                    .localizedCaseInsensitiveContains(query) ? 4.0 : 0.0

                let coverage = Double(bodyHits) / Double(queryTokens.count)
                let score = Double(titleHits * 4 + keywordHits * 3 + bodyHits) + coverage + phraseBonus
                guard score > 0 else { return nil }
                return RetrievedPassage(article: article, score: score)
            }
            .sorted {
                if $0.score == $1.score { return $0.article.id < $1.article.id }
                return $0.score > $1.score
            }
            .prefix(max(1, limit))
            .map { $0 }
    }

    static func tokens(in text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "can", "do", "for", "from",
            "how", "i", "in", "is", "it", "my", "of", "on", "or", "the", "to", "what",
            "when", "where", "with"
        ]
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let pieces = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(pieces.filter { $0.count > 1 && !stopWords.contains($0) })
    }
}
