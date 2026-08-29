import Foundation

public enum ExpertGroundingReason: String, Codable, Sendable {
    case exactReviewedIntent = "exact_reviewed_intent"
    case resolvedHistory = "resolved_history"
    case rankedReviewedIntent = "ranked_reviewed_intent"
}

public enum ExpertCoverageDecision: String, Codable, Sendable {
    case sufficient
    case insufficient
    case notNeeded = "not_needed"
}

public enum ExpertPlanDisposition: String, Codable, Sendable {
    case grounded
    case clarify
    case ordinary
}

public struct ExpertEvidencePlan: Equatable, Sendable {
    public let disposition: ExpertPlanDisposition
    public let riskClass: ExpertRiskClass
    public let evidenceIndexes: [Int]
    public let coverage: ExpertCoverageDecision
    public let clarificationTarget: String

    public init(
        disposition: ExpertPlanDisposition,
        riskClass: ExpertRiskClass,
        evidenceIndexes: [Int],
        coverage: ExpertCoverageDecision,
        clarificationTarget: String
    ) {
        self.disposition = disposition
        self.riskClass = riskClass
        self.evidenceIndexes = evidenceIndexes
        self.coverage = coverage
        self.clarificationTarget = clarificationTarget
    }
}

public enum ExpertEvidencePlanError: Error, Equatable, Sendable {
    case malformed
    case invalidEvidence
    case unsafeDisposition
    case invalidCoverage
    case invalidClarification
}

public struct ExpertEvidencePlanCodec: Sendable {
    private struct CompactPlan: Decodable {
        let disposition: ExpertPlanDisposition
        let riskClass: ExpertRiskClass
        let evidenceIndexes: [Int]
        let coverage: ExpertCoverageDecision
        let clarificationTarget: String

        private enum CodingKeys: String, CodingKey {
            case disposition = "d"
            case riskClass = "r"
            case evidenceIndexes = "e"
            case coverage = "c"
            case clarificationTarget = "q"
        }
    }

    public init() {}

    public func decodeAndValidate(
        _ value: String,
        candidates: [RetrievedEvidenceScenario],
        requiresSafetyResponse: Bool,
        requiresClarification: Bool,
        requiredCandidateIndexes: [Int] = []
    ) throws -> ExpertEvidencePlan {
        guard let start = value.firstIndex(of: "{"),
              let end = value.lastIndex(of: "}"),
              start <= end,
              let data = String(value[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              Set(object.keys) == ["d", "r", "e", "c", "q"],
              let decoded = try? JSONDecoder().decode(CompactPlan.self, from: data)
        else { throw ExpertEvidencePlanError.malformed }

        let indexes = decoded.evidenceIndexes
        guard indexes.count <= 3,
              Set(indexes).count == indexes.count,
              indexes.allSatisfy({ candidates.indices.contains($0 - 1) })
        else { throw ExpertEvidencePlanError.invalidEvidence }

        if requiresClarification, decoded.disposition != .clarify {
            throw ExpertEvidencePlanError.unsafeDisposition
        }
        if !requiredCandidateIndexes.isEmpty {
            guard decoded.disposition == .grounded,
                  Set(requiredCandidateIndexes).isSubset(of: Set(indexes))
            else { throw ExpertEvidencePlanError.unsafeDisposition }
        }

        switch decoded.disposition {
        case .grounded:
            guard decoded.coverage == .sufficient,
                  !indexes.isEmpty,
                  decoded.clarificationTarget.isEmpty
            else { throw ExpertEvidencePlanError.invalidCoverage }
        case .clarify:
            guard decoded.coverage == .insufficient,
                  indexes.isEmpty,
                  (1...160).contains(decoded.clarificationTarget.count)
            else { throw ExpertEvidencePlanError.invalidClarification }
        case .ordinary:
            guard !requiresSafetyResponse,
                  decoded.riskClass == .low,
                  decoded.coverage == .notNeeded,
                  indexes.isEmpty,
                  decoded.clarificationTarget.isEmpty
            else { throw ExpertEvidencePlanError.unsafeDisposition }
        }
        return ExpertEvidencePlan(
            disposition: decoded.disposition,
            riskClass: decoded.riskClass,
            evidenceIndexes: indexes,
            coverage: decoded.coverage,
            clarificationTarget: decoded.clarificationTarget
        )
    }
}

public struct ExpertAttributedSentence: Codable, Equatable, Sendable {
    public let text: String
    public let evidenceIndexes: [Int]

    public init(text: String, evidenceIndexes: [Int]) {
        self.text = text
        self.evidenceIndexes = evidenceIndexes
    }

    private enum CodingKeys: String, CodingKey {
        case text = "a"
        case evidenceIndexes = "e"
    }
}

public struct ExpertAttributedAnswer: Codable, Equatable, Sendable {
    public let sentences: [ExpertAttributedSentence]

    public init(sentences: [ExpertAttributedSentence]) {
        self.sentences = sentences
    }

    private enum CodingKeys: String, CodingKey {
        case sentences = "s"
    }

    public var text: String {
        sentences.map(\.text).joined(separator: " ")
    }

    public var evidenceIndexes: [Int] {
        Array(Set(sentences.flatMap(\.evidenceIndexes))).sorted()
    }
}

public enum ExpertAttributedAnswerError: Error, Equatable, Sendable {
    case malformed
    case invalidSentenceCount
    case invalidSentence(Int)
    case invalidEvidence(Int)
}

public struct ExpertAttributedAnswerCodec: Sendable {
    public init() {}

    public func decodeAndValidate(
        _ value: String,
        evidenceCount: Int
    ) throws -> ExpertAttributedAnswer {
        guard let start = value.firstIndex(of: "{"),
              let end = value.lastIndex(of: "}"),
              start <= end,
              let data = String(value[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              Set(object.keys) == ["s"],
              let rawSentences = object["s"] as? [[String: Any]],
              rawSentences.allSatisfy({ Set($0.keys) == ["a", "e"] }),
              let answer = try? JSONDecoder().decode(
                ExpertAttributedAnswer.self,
                from: data
              )
        else { throw ExpertAttributedAnswerError.malformed }
        guard (2...5).contains(answer.sentences.count) else {
            throw ExpertAttributedAnswerError.invalidSentenceCount
        }
        for (offset, sentence) in answer.sentences.enumerated() {
            let trimmed = sentence.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard (15...260).contains(trimmed.count),
                  trimmed == sentence.text,
                  !trimmed.contains("\n"),
                  trimmed.last.map({ ".!?".contains($0) }) == true,
                  Self.hasBalancedDelimiters(trimmed),
                  !GroundedResponseCodec.containsControlLeakage(trimmed)
            else { throw ExpertAttributedAnswerError.invalidSentence(offset + 1) }
            guard (1...3).contains(sentence.evidenceIndexes.count),
                  Set(sentence.evidenceIndexes).count
                    == sentence.evidenceIndexes.count,
                  sentence.evidenceIndexes.allSatisfy({
                      (1...evidenceCount).contains($0)
                  })
            else { throw ExpertAttributedAnswerError.invalidEvidence(offset + 1) }
        }
        return answer
    }

    private static func hasBalancedDelimiters(_ value: String) -> Bool {
        let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        var stack: [Character] = []
        for character in value {
            if pairs.values.contains(character) {
                stack.append(character)
            } else if let opener = pairs[character] {
                guard stack.popLast() == opener else { return false }
            }
        }
        return stack.isEmpty
    }
}

public enum ExpertTurnIntentError: Error, Equatable, Sendable {
    case malformed
}

public enum ResponseLanguage: String, Codable, Equatable, Sendable {
    case english = "en"
    case chinese = "zh"

    public static func detect(in value: String) -> ResponseLanguage {
        value.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        } ? .chinese : .english
    }

    public var instruction: String {
        switch self {
        case .english: return "Respond in English."
        case .chinese: return "Use clear Simplified Chinese for the complete answer."
        }
    }
}

public struct TurnRoutingDecision: Equatable, Sendable {
    public let intent: ExpertTurnIntent
    public let responseLanguage: ResponseLanguage
    public let retrievalQuery: String

    public init(
        intent: ExpertTurnIntent,
        responseLanguage: ResponseLanguage,
        retrievalQuery: String
    ) {
        self.intent = intent
        self.responseLanguage = responseLanguage
        self.retrievalQuery = retrievalQuery
    }
}

public struct TurnRoutingDecisionCodec: Sendable {
    private struct CompactDecision: Decodable {
        let intent: String
        let language: String
        let query: String

        private enum CodingKeys: String, CodingKey {
            case intent = "t"
            case language = "l"
            case query = "q"
        }
    }

    public init() {}

    public func decodeAndValidate(_ value: String) throws -> TurnRoutingDecision {
        guard let start = value.firstIndex(of: "{"),
              let end = value.lastIndex(of: "}"),
              start <= end,
              let data = String(value[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              Set(object.keys) == ["t", "l", "q"],
              let decoded = try? JSONDecoder().decode(
                CompactDecision.self,
                from: data
              ),
              let language = ResponseLanguage(rawValue: decoded.language)
        else { throw ExpertTurnIntentError.malformed }

        let intent: ExpertTurnIntent
        switch decoded.intent {
        case "general": intent = .generalQuestion
        case "survival": intent = .survivalQuestion
        default: throw ExpertTurnIntentError.malformed
        }

        let query = decoded.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count <= 160,
              !query.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }),
              (intent == .generalQuestion ? query.isEmpty : !query.isEmpty)
        else { throw ExpertTurnIntentError.malformed }

        return TurnRoutingDecision(
            intent: intent,
            responseLanguage: language,
            retrievalQuery: query
        )
    }
}

public enum ExpertAnswerSafetyError: Error, Equatable, Sendable {
    case unreviewedEvidence
    case unsupportedNumber(String)
    case unsupportedClaim(
        sentence: Int,
        terms: [String],
        permittedClaims: [Int]
    )
    case prohibitedClaim
    case insufficientActionCoverage
    case insufficientWarningCoverage
    case unusedEvidence(Int)
    case wrongClaimAttribution(sentence: Int, claim: Int)
    case inapplicableWarning(sentence: Int, claim: Int)
    case missingEscalation
    case unsupportedCondition(sentence: Int)
    case incompleteEvidenceSet
}

public struct ExpertAnswerSafetyValidator: Sendable {
    private static let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "before", "by",
        "for", "from", "if", "in", "is", "it", "of", "on", "or",
        "that", "the", "then", "this", "to", "use", "with", "you",
        "your",
    ]

    public init() {}

    public func validate(
        answer: ExpertAttributedAnswer,
        bundle: EvidenceBundle
    ) throws {
        guard !bundle.scenarios.isEmpty,
              bundle.scenarios.allSatisfy({
                  !$0.scenario.claims.isEmpty
                    && $0.scenario.claims.allSatisfy({ !$0.sourceIDs.isEmpty })
              })
        else { throw ExpertAnswerSafetyError.unreviewedEvidence }
        for (offset, sentence) in answer.sentences.enumerated() {
            let citedClaims = sentence.evidenceIndexes.map {
                bundle.claims[$0 - 1]
            }
            try validateNumbers(
                in: sentence.text,
                allowed: Set(citedClaims
                    .flatMap(\.allowedNumericFacts)
                    .map { $0.token.lowercased() })
            )
            try validateProhibitedClaims(sentence.text)
            let sentenceTerms = Self.alignedContentTerms(sentence.text)
            let evidenceTerms = Self.alignedContentTerms(
                citedClaims.map(\.text).joined(separator: " ")
            )
            let unsupported = sentenceTerms
                .subtracting(evidenceTerms)
                .subtracting(Self.alignedGeneralProseTerms)
                .filter { $0.count >= 4 }
                .sorted()
            let unsupportedProcedures = Set(unsupported)
                .intersection(Self.alignedRestrictedProcedureTerms)
            guard unsupportedProcedures.isEmpty,
                  unsupported.count <= 1
            else {
                throw ExpertAnswerSafetyError.unsupportedClaim(
                    sentence: offset + 1,
                    terms: Array((unsupportedProcedures.isEmpty
                        ? unsupported
                        : unsupportedProcedures.sorted()).prefix(6)),
                    permittedClaims: sentence.evidenceIndexes
                )
            }
            guard sentenceTerms.intersection(evidenceTerms).count >= 3 else {
                throw ExpertAnswerSafetyError.insufficientActionCoverage
            }
        }

        let answerTerms = Self.alignedContentTerms(answer.text)
        let usedIndexes = Set(answer.evidenceIndexes)
        let usedClaims = usedIndexes.sorted().map { bundle.claims[$0 - 1] }
        let actionTerms = Self.alignedContentTerms(
            usedClaims.filter { $0.kind == .action }.map(\.text)
                .joined(separator: " ")
        )
        guard answerTerms.intersection(actionTerms).count >= 3 else {
            throw ExpertAnswerSafetyError.insufficientActionCoverage
        }
        let safetyTerms = Self.alignedContentTerms(
            usedClaims.filter {
                $0.kind == .contraindication || $0.kind == .escalation
                    || $0.kind == .stopCondition
            }.map(\.text)
                .joined(separator: " ")
        )
        guard !safetyTerms.isEmpty,
              !answerTerms.isDisjoint(with: safetyTerms)
        else { throw ExpertAnswerSafetyError.insufficientWarningCoverage }
    }

    public func validate(
        answer: String,
        passage: RetrievedPassage
    ) throws {
        let article = passage.article
        guard article.reviewed, article.manualReference != nil else {
            throw ExpertAnswerSafetyError.unreviewedEvidence
        }
        let lower = answer.lowercased()
        let reviewed = article.searchableText.lowercased()
        let numericPattern = #"\b\d+(?:\.\d+)?(?:%|°|[a-z]+)?\b"#
        if let expression = try? NSRegularExpression(pattern: numericPattern) {
            let range = NSRange(answer.startIndex..., in: answer)
            for match in expression.matches(in: answer, range: range) {
                guard let matchRange = Range(match.range, in: answer) else {
                    continue
                }
                let token = answer[matchRange].lowercased()
                if !reviewed.contains(token) {
                    throw ExpertAnswerSafetyError.unsupportedNumber(token)
                }
            }
        }

        let absoluteClaims = [
            "definitely safe", "completely safe", "this confirms",
            "the photo proves", "diagnosed with",
            "it is infected", "not infected", "chemically safe",
            "safe route", "structurally sound", "will not collapse",
            "confirmed safe", "unless it is safe", "unless it's safe",
        ]
        guard !absoluteClaims.contains(where: {
            Self.containsAffirmativeClaim(lower, phrase: $0)
        }) else {
            throw ExpertAnswerSafetyError.prohibitedClaim
        }

        let unsupportedObservedClaims = [
            "certified container", "may indicate contamination",
            "tree is struck", "use water to extinguish",
        ]
        guard !unsupportedObservedClaims.contains(where: {
            lower.contains($0) && !reviewed.contains($0)
        }) else { throw ExpertAnswerSafetyError.prohibitedClaim }

        let answerTerms = Self.contentTerms(answer)
        let actionTerms = Self.contentTerms(
            ([article.summary] + article.steps).joined(separator: " ")
        )
        guard answerTerms.intersection(actionTerms).count >= 3 else {
            throw ExpertAnswerSafetyError.insufficientActionCoverage
        }
        let warningTerms = Self.contentTerms(article.warnings.joined(separator: " "))
        guard GroundedResponseCodec.hasExplicitSafetyLimit(answer),
              !warningTerms.isEmpty,
              !answerTerms.isDisjoint(with: warningTerms)
        else { throw ExpertAnswerSafetyError.insufficientWarningCoverage }
    }

    private static func contentTerms(_ value: String) -> Set<String> {
        RetrievalEngine.tokens(in: value).subtracting(stopwords)
    }

    private func validateNumbers(
        in answer: String,
        allowed: Set<String>
    ) throws {
        let numericPattern = #"\b\d+(?:[,.]\d+)*(?:%|°|[a-zA-Z]+)?\b"#
        guard let expression = try? NSRegularExpression(pattern: numericPattern)
        else { return }
        let range = NSRange(answer.startIndex..., in: answer)
        for match in expression.matches(in: answer, range: range) {
            guard let matchRange = Range(match.range, in: answer) else {
                continue
            }
            let token = answer[matchRange].lowercased()
            if !allowed.contains(token) {
                throw ExpertAnswerSafetyError.unsupportedNumber(String(token))
            }
        }
    }

    private func validateProhibitedClaims(_ answer: String) throws {
        let lower = answer.lowercased()
        let absoluteClaims = [
            "definitely safe", "completely safe", "this confirms",
            "the photo proves", "diagnosed with", "it is infected",
            "not infected", "chemically safe", "safe route",
            "structurally sound", "will not collapse", "confirmed safe",
            "only safe way", "no exceptions",
        ]
        guard !absoluteClaims.contains(where: {
            Self.containsAffirmativeClaim(lower, phrase: $0)
        }) else { throw ExpertAnswerSafetyError.prohibitedClaim }
    }

    private static func alignedContentTerms(_ value: String) -> Set<String> {
        Set(contentTerms(value).map { term in
            let aliases: [String: String] = [
                "metres": "meter", "meters": "meter",
                "litres": "liter", "liters": "liter",
                "feet": "foot", "children": "child",
                "apply": "press", "pressure": "press",
                "firmly": "firm", "continuous": "maintain",
                "using": "use", "without": "omit",
            ]
            if let alias = aliases[term] { return alias }
            if term.count > 6, term.hasSuffix("ing") {
                return String(term.dropLast(3))
            }
            if term.count > 5, term.hasSuffix("ed") {
                return String(term.dropLast(2))
            }
            if term.count > 5, term.hasSuffix("es") {
                return String(term.dropLast(2))
            }
            if term.count > 4, term.hasSuffix("s") {
                return String(term.dropLast())
            }
            return term
        })
    }

    private static let generalProseTerms: Set<String> = [
        "action", "available", "avoid", "because", "before", "carefully",
        "begin", "condition", "continue", "control", "current", "danger",
        "dangerous", "directly", "effective", "ensure", "essential",
        "extinguish", "help", "immediate", "immediately", "important", "instead",
        "keep", "needed", "person", "possible", "prevent", "reduce", "remain",
        "risk", "safe", "safely", "safety", "situation", "slowly", "stop",
        "unsafe", "until", "warning", "worse", "worsen",
    ]

    private static let alignedGeneralProseTerms = alignedContentTerms(
        generalProseTerms.joined(separator: " ")
    )

    private static let restrictedProcedureTerms: Set<String> = [
        "airway", "amputate", "antibiotic", "aspirin", "bandage",
        "bleach", "breathe", "breathing", "chemical", "compress",
        "cpr", "diagnose", "drill", "drug", "epinephrine", "explode",
        "explosion", "fan", "infected", "inject", "medicine", "pathogen",
        "splint", "surgery", "test", "tourniquet", "ventilate",
    ]

    private static let alignedRestrictedProcedureTerms = alignedContentTerms(
        restrictedProcedureTerms.joined(separator: " ")
    )

    private static func containsAffirmativeClaim(
        _ answer: String,
        phrase: String
    ) -> Bool {
        guard let range = answer.range(of: phrase) else { return false }
        let distance = answer.distance(from: answer.startIndex, to: range.lowerBound)
        let start = answer.index(
            range.lowerBound,
            offsetBy: -min(28, distance)
        )
        let prefix = answer[start..<range.lowerBound]
        let negations = [
            "cannot confirm ", "can't confirm ", "do not assume ",
            "don't assume ", "not possible to confirm ", "never assume ",
        ]
        return !negations.contains(where: prefix.hasSuffix)
    }
}
