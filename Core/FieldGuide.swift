import Foundation

public enum FieldGuideSectionKind: String, Codable, Hashable, Sendable {
    case text
    case bullets
    case steps
    case callout
}

public enum FieldGuideVisualRole: String, Codable, Hashable, Sendable {
    case primary
    case secondary
    case related
}

public struct FieldGuideSection: Codable, Hashable, Sendable, Identifiable {
    public let heading: String?
    public let kind: FieldGuideSectionKind
    public let content: String

    public var id: String { "\(heading ?? "intro")-\(content)" }
}

public struct FieldGuideVisualPlacement: Codable, Hashable, Sendable, Identifiable {
    public let assetID: String
    public let role: FieldGuideVisualRole

    public var id: String { "\(assetID)-\(role.rawValue)" }
}

public struct FieldGuideVisual: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let imageName: String
    public let sourceFilename: String
    public let title: String
    public let caption: String
    public let altText: String
    public let searchTags: [String]
    public let priority: String
}

public struct FieldGuideSkill: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let order: Int
    public let title: String
    public let purpose: String
    public let difficulty: String?
    public let sections: [FieldGuideSection]
    public let aliases: [String]
    public let tags: [String]
    public let relatedSkillIDs: [String]
    public let visuals: [FieldGuideVisualPlacement]
}

public struct FieldGuideChapter: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let order: Int
    public let title: String
    public let purpose: String
    public let symbol: String
    public let theme: String
    public let skills: [FieldGuideSkill]
}

public struct FieldGuidePriority: Codable, Hashable, Sendable, Identifiable {
    public let title: String
    public let text: String

    public var id: String { title }
}

public struct FieldGuideBook: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let title: String
    public let subtitle: String
    public let introduction: String
    public let chapters: [FieldGuideChapter]
    public let visuals: [FieldGuideVisual]
    public let priorityCard: [FieldGuidePriority]
    public let masterySkills: [String]
}

public struct FieldGuideSearchResult: Hashable, Sendable, Identifiable {
    public let chapter: FieldGuideChapter
    public let skill: FieldGuideSkill
    public let excerpt: String
    public let score: Int

    public var id: String { skill.id }
}

public enum FieldGuideError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case emptyBook
    case duplicateID(String)
    case invalidOrder(String)
    case missingVisual(String)
    case missingRelatedSkill(String)
    case invalidVisualMetadata(String)
}

public struct FieldGuideStore: Sendable {
    public let book: FieldGuideBook
    private let chaptersByID: [String: FieldGuideChapter]
    private let skillsByID: [String: FieldGuideSkill]
    private let visualsByID: [String: FieldGuideVisual]

    public init(book: FieldGuideBook) throws {
        guard book.schemaVersion == 1 else {
            throw FieldGuideError.unsupportedSchema(book.schemaVersion)
        }
        guard !book.chapters.isEmpty else { throw FieldGuideError.emptyBook }

        let chapterIDs = book.chapters.map(\.id)
        guard Set(chapterIDs).count == chapterIDs.count else {
            throw FieldGuideError.duplicateID("chapter")
        }
        let skills = book.chapters.flatMap(\.skills)
        let skillIDs = skills.map(\.id)
        guard Set(skillIDs).count == skillIDs.count else {
            throw FieldGuideError.duplicateID("skill")
        }
        let visualIDs = book.visuals.map(\.id)
        guard Set(visualIDs).count == visualIDs.count else {
            throw FieldGuideError.duplicateID("visual")
        }
        for chapter in book.chapters {
            guard chapter.order > 0,
                  chapter.skills.map(\.order) == Array(1...chapter.skills.count)
            else { throw FieldGuideError.invalidOrder(chapter.id) }
        }
        let visualSet = Set(visualIDs)
        let skillSet = Set(skillIDs)
        for visual in book.visuals where visual.title.isEmpty
            || visual.caption.isEmpty || visual.altText.isEmpty {
            throw FieldGuideError.invalidVisualMetadata(visual.id)
        }
        for skill in skills {
            for placement in skill.visuals where !visualSet.contains(placement.assetID) {
                throw FieldGuideError.missingVisual(placement.assetID)
            }
            for relatedID in skill.relatedSkillIDs where !skillSet.contains(relatedID) {
                throw FieldGuideError.missingRelatedSkill(relatedID)
            }
        }

        self.book = book
        chaptersByID = Dictionary(uniqueKeysWithValues: book.chapters.map { ($0.id, $0) })
        skillsByID = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        visualsByID = Dictionary(uniqueKeysWithValues: book.visuals.map { ($0.id, $0) })
    }

    public static func load(url: URL) throws -> FieldGuideStore {
        let book = try JSONDecoder().decode(
            FieldGuideBook.self,
            from: Data(contentsOf: url)
        )
        return try FieldGuideStore(book: book)
    }

    public func chapter(id: String) -> FieldGuideChapter? { chaptersByID[id] }
    public func skill(id: String) -> FieldGuideSkill? { skillsByID[id] }
    public func visual(id: String) -> FieldGuideVisual? { visualsByID[id] }

    public func chapter(containing skill: FieldGuideSkill) -> FieldGuideChapter? {
        book.chapters.first { chapter in chapter.skills.contains { $0.id == skill.id } }
    }

    public func adjacentSkills(to skill: FieldGuideSkill) -> (previous: FieldGuideSkill?, next: FieldGuideSkill?) {
        guard let chapter = chapter(containing: skill),
              let index = chapter.skills.firstIndex(where: { $0.id == skill.id })
        else { return (nil, nil) }
        return (
            index > chapter.skills.startIndex ? chapter.skills[index - 1] : nil,
            index + 1 < chapter.skills.endIndex ? chapter.skills[index + 1] : nil
        )
    }

    public func search(_ query: String) -> [FieldGuideSearchResult] {
        let terms = Self.tokens(query)
        guard !terms.isEmpty else { return [] }
        var results: [FieldGuideSearchResult] = []
        for chapter in book.chapters {
            for skill in chapter.skills {
                let title = Self.normalized(skill.title)
                let aliases = skill.aliases.map(Self.normalized)
                let tags = skill.tags.map(Self.normalized)
                let headings = skill.sections.compactMap(\.heading).map(Self.normalized)
                let body = Self.normalized(([skill.purpose] + skill.sections.map(\.content)).joined(separator: " "))
                let visualText = skill.visuals.compactMap { visualsByID[$0.assetID] }.flatMap {
                    [$0.title, $0.caption, $0.altText] + $0.searchTags
                }.map(Self.normalized)
                var total = 0
                var matchedAll = true
                for term in terms {
                    let score: Int
                    if Self.matches(term, in: title) || aliases.contains(where: { Self.matches(term, in: $0) }) {
                        score = 100
                    } else if tags.contains(where: { Self.matches(term, in: $0) })
                                || headings.contains(where: { Self.matches(term, in: $0) }) {
                        score = 60
                    } else if visualText.contains(where: { Self.matches(term, in: $0) }) {
                        score = 40
                    } else if Self.matches(term, in: body) {
                        score = 20
                    } else {
                        score = 0
                        matchedAll = false
                    }
                    total += score
                }
                guard matchedAll else { continue }
                results.append(FieldGuideSearchResult(
                    chapter: chapter,
                    skill: skill,
                    excerpt: Self.excerpt(for: skill, matching: terms),
                    score: total
                ))
            }
        }
        return results.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.chapter.order != $1.chapter.order { return $0.chapter.order < $1.chapter.order }
            return $0.skill.order < $1.skill.order
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func tokens(_ value: String) -> [String] {
        normalized(value).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func matches(_ term: String, in value: String) -> Bool {
        value.contains(term) || value.split { !$0.isLetter && !$0.isNumber }.contains {
            $0.hasPrefix(term)
        }
    }

    private static func excerpt(for skill: FieldGuideSkill, matching terms: [String]) -> String {
        let candidate = skill.sections.first {
            let value = normalized($0.content)
            return terms.contains { matches($0, in: value) }
        }?.content ?? skill.purpose
        let plain = candidate
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "- ", with: "")
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        return plain.count > 150 ? String(plain.prefix(147)) + "…" : plain
    }
}

public enum FieldGuideRoute: Hashable, Sendable {
    case chapter(String)
    case skill(String)
}
