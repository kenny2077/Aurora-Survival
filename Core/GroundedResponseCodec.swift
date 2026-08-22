import Foundation

public enum GroundedResponseCodecError: Error, Equatable {
    case noJSONObject
    case invalidJSON
}

public struct GroundedResponseCodec: Sendable {
    private let validator: GroundedResponseValidator

    public init(validator: GroundedResponseValidator = GroundedResponseValidator()) {
        self.validator = validator
    }

    public func decodeValidateAndRender(
        _ generated: String,
        evidence: [RetrievedPassage]
    ) throws -> String {
        let response = try decodeAndValidate(generated, evidence: evidence)
        return try renderValidated(response, evidence: evidence)
    }

    public func decodeConversationalAndValidate(
        _ generated: String,
        evidence: [RetrievedPassage],
        purpose: ModelPromptPurpose? = nil,
        question: String? = nil,
        tier: ModelTier = .lite
    ) throws -> ConversationalGroundedResponse {
        guard let json = Self.jsonObjectData(in: generated) else {
            throw GroundedResponseCodecError.noJSONObject
        }
        guard let decision = try? JSONDecoder().decode(
            CompactConversationalDecision.self,
            from: json
        ) else {
            throw GroundedResponseCodecError.invalidJSON
        }

        var answer = decision.answer
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(
                of: #"(^|\s)[1-4]\.\s+"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(of: ".,", with: ".")
            .replacingOccurrences(of: "!,", with: "!")
            .replacingOccurrences(of: "?,", with: "?")
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if tier != .expert {
            answer = answer.replacingOccurrences(
                of: #"\bWARNING:\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        if answer.hasSuffix(".,") || answer.hasSuffix("!,")
                || answer.hasSuffix("?,") || answer.hasSuffix("…,") {
            answer.removeLast()
        }
        let effectivePurpose = purpose ?? (evidence.isEmpty ? .ordinary : .grounded)
        guard Self.isUsableConversationalAnswer(
            answer,
            purpose: effectivePurpose,
            question: question,
            tier: tier
        ) else {
            throw GroundedResponseError.invalidConversationalAnswer
        }
        if effectivePurpose == .grounded, tier != .expert {
            let lowercasedAnswer = answer.lowercased()
            guard !evidence.contains(where: {
                lowercasedAnswer.contains($0.article.title.lowercased())
            }) else {
                throw GroundedResponseError.invalidConversationalAnswer
            }
        }
        let followUp = decision.followUp?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let followUp, followUp.isEmpty || followUp.count > 96 {
            throw GroundedResponseError.invalidFollowUp
        }

        let indexes = decision.evidenceIndexes
        guard indexes.count <= 2,
              Set(indexes).count == indexes.count,
              (effectivePurpose == .grounded ? !indexes.isEmpty : indexes.isEmpty)
        else {
            throw GroundedResponseError.invalidConversationalEvidence
        }
        if tier == .expert, effectivePurpose == .grounded,
           indexes != [1] {
            throw GroundedResponseError.invalidConversationalEvidence
        }
        let evidenceIDs = try indexes.map { index -> String in
            let offset = index - 1
            guard evidence.indices.contains(offset) else {
                throw GroundedResponseError.unknownEvidenceIndex(index)
            }
            return evidence[offset].article.id
        }
        let procedureID: String?
        if let procedureIndex = decision.procedureIndex {
            let offset = procedureIndex - 1
            guard evidence.indices.contains(offset) else {
                throw GroundedResponseError.unknownEvidenceIndex(
                    procedureIndex
                )
            }
            guard indexes.contains(procedureIndex) else {
                throw GroundedResponseError.procedureRequiresCitedEvidence
            }
            procedureID = evidence[offset].article.id
        } else {
            procedureID = nil
        }

        return ConversationalGroundedResponse(
            answer: answer,
            evidenceIDs: evidenceIDs,
            procedureID: procedureID,
            followUp: followUp
        )
    }

    public func renderConversational(
        _ response: ConversationalGroundedResponse,
        evidence: [RetrievedPassage]
    ) -> String {
        response.answer
    }

    public func decodeAndValidate(
        _ generated: String,
        evidence: [RetrievedPassage]
    ) throws -> GroundedResponse {
        guard let json = Self.jsonObjectData(in: generated) else {
            throw GroundedResponseCodecError.noJSONObject
        }
        let decoder = JSONDecoder()
        let response: GroundedResponse
        if let decoded = try? decoder.decode(GroundedResponse.self, from: json) {
            response = decoded
        } else if let decision = try? decoder.decode(
            CompactGroundedDecision.self,
            from: json
        ) {
            response = try decision.expanded(evidence: evidence)
        } else {
            throw GroundedResponseCodecError.invalidJSON
        }

        let evidenceIDs = Set(evidence.map(\.article.id))
        let procedureIDs = evidenceIDs
        let stepMap = Self.stepMap(for: evidence)
        let warnings = Set(evidence.flatMap(\.article.warnings))
        if let procedureID = response.procedureID,
           let procedure = evidence.first(where: {
               $0.article.id == procedureID
           }),
           procedure.article.domain != response.domain {
            throw GroundedResponseError.procedureDomainMismatch(procedureID)
        }
        try validator.validate(
            response,
            availableEvidenceIDs: evidenceIDs,
            approvedProcedureIDs: procedureIDs,
            approvedStepIDs: Set(stepMap.keys),
            approvedWarnings: warnings
        )
        return response
    }

    public func renderValidated(
        _ response: GroundedResponse,
        evidence: [RetrievedPassage]
    ) throws -> String {
        Self.render(
            response,
            approvedSteps: Self.approvedSteps(
                for: response.procedureID,
                evidence: evidence
            ),
            approvedWarnings: Self.approvedWarnings(
                for: response.procedureID,
                evidence: evidence
            )
        )
    }

    private static func jsonObjectData(in value: String) -> Data? {
        guard let start = value.firstIndex(of: "{"),
              let end = value.lastIndex(of: "}"),
              start <= end
        else {
            return nil
        }
        return Data(value[start...end].utf8)
    }

    private static func isUsableConversationalAnswer(
        _ answer: String,
        purpose: ModelPromptPurpose,
        question: String?,
        tier: ModelTier
    ) -> Bool {
        guard !answer.isEmpty,
              answer.count <= (tier == .expert ? 900 : 440),
              let last = answer.last,
              ".!?…".contains(last)
        else {
            return false
        }

        let wordCount = answer.split(whereSeparator: \.isWhitespace).count
        let sentenceCount = answer.split {
            ".!?…".contains($0)
        }.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        switch purpose {
        case .ordinary, .nativeVisionAnswer:
            break
        case .grounded:
            let wordRange = tier == .expert ? 45...95 : 28...70
            let sentenceRange = tier == .expert ? 2...5 : 2...4
            guard wordRange.contains(wordCount),
                  sentenceRange.contains(sentenceCount),
                  Self.hasWarningOrStopCondition(answer) else {
                return false
            }
        case .clarification:
            let wordRange = tier == .expert ? 25...60 : 18...45
            guard wordRange.contains(wordCount),
                  Self.isClarificationRequest(answer) else {
                return false
            }
        case .incidentFallback:
            guard (24...75).contains(wordCount),
                  (1...6).contains(sentenceCount),
                  !Self.impersonatesUser(answer, question: question) else {
                return false
            }
        case .incidentIntake:
            guard (14...40).contains(wordCount),
                  (1...3).contains(sentenceCount),
                  Self.isIncidentIntakeRequest(answer) else {
                return false
            }
        case .expertIntent:
            return false
        }

        let structuralMarkers = ["FIELD MANUAL", "USER MESSAGE"]
        if structuralMarkers.contains(where: answer.contains) {
            return false
        }
        let lowercased = answer.lowercased()
        let unsafeInstructions = [
            "eat an unknown", "consume an unknown", "taste an unknown",
            "sample an unknown", "drink untreated water", "induce vomiting",
            "make yourself vomit", "touch a live wire", "touch the live wire",
            "pour water on an electrical", "drive yourself while impaired",
            "can move it with a stick", "can be moved with a stick safely",
            "likely an edible species", "looks and smells normal, it's likely safe to eat",
            "not infected yet", "remove it using tweezers or a magnet",
            "burn the tick", "smother the tick",
        ]
        guard !unsafeInstructions.contains(where: {
            Self.containsAffirmativeInstruction(lowercased, phrase: $0)
        }) else {
            return false
        }
        return !containsControlLeakage(answer)
    }

    static func containsControlLeakage(_ answer: String) -> Bool {
        let lowercased = answer.lowercased()
        let leakedInstructions = [
            "actions:", "cited claim", "citation markers", "do not invent steps",
            "evidence-index", "evidence index", "extra keys", "goal:",
            "internal correction", "no markdown", "no procedures",
            "output must be", "page numbers inside", "response check",
            "return exactly", "return valid json", "reviewed evidence records",
            "reviewed excerpt", "scenario id", "schema", "selected reviewed", "source names",
            "title:", "valid json", "\"a\":", "\"e\":", "\"s\":",
            "e=[]",
        ]
        if leakedInstructions.contains(where: lowercased.contains) { return true }
        if answer.range(of: #"\[\d+\]"#, options: .regularExpression) != nil {
            return true
        }
        return answer.range(
            of: #"[;,:]\s+[?!.](?:\s|$)"#,
            options: .regularExpression
        ) != nil
    }

    private static func impersonatesUser(
        _ answer: String,
        question: String?
    ) -> Bool {
        guard let question else { return false }
        let user = question.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard user.hasPrefix("i ") || user.hasPrefix("i'm ")
                || user.hasPrefix("i am ") || user.hasPrefix("my ") else {
            return false
        }
        let response = answer.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedFirstPerson = [
            "i'm sorry", "i am sorry", "i understand", "i recommend", "i can ",
        ]
        if allowedFirstPerson.contains(where: response.hasPrefix) {
            return false
        }
        let selfClaimPrefixes = [
            "i ", "i'm ", "i am ", "my ", "i feel ", "i have ", "i need ",
            "i dropped ", "i lost ", "i was ",
        ]
        guard selfClaimPrefixes.contains(where: response.hasPrefix) else {
            return false
        }
        let generic: Set<String> = ["am", "are", "have", "the", "this", "with"]
        let userTerms = RetrievalEngine.tokens(in: user).subtracting(generic)
        let firstSentence = response.split(whereSeparator: { ".!?…".contains($0) })
            .first.map(String.init) ?? response
        let responseTerms = RetrievalEngine.tokens(in: firstSentence).subtracting(generic)
        return !userTerms.isDisjoint(with: responseTerms)
    }

    static func hasExplicitSafetyLimit(_ answer: String) -> Bool {
        let lowercased = answer.lowercased()
        let signals = [
            "avoid", "caution", "cautious", "danger", "do not", "don't", "emergency",
            "hazard", "never", "risk", "stop", "threat", "unsafe", "warning",
        ]
        return signals.contains(where: lowercased.contains)
    }

    private static func hasWarningOrStopCondition(_ answer: String) -> Bool {
        hasExplicitSafetyLimit(answer)
    }

    private static func containsAffirmativeInstruction(
        _ answer: String,
        phrase: String
    ) -> Bool {
        var searchStart = answer.startIndex
        while let range = answer.range(
            of: phrase,
            range: searchStart..<answer.endIndex
        ) {
            let prefixStart = answer.index(
                range.lowerBound,
                offsetBy: -min(24, answer.distance(
                    from: answer.startIndex,
                    to: range.lowerBound
                ))
            )
            let prefix = answer[prefixStart..<range.lowerBound]
            let negations = ["avoid ", "do not ", "don't ", "never ", "not to "]
            if !negations.contains(where: prefix.hasSuffix) {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isClarificationRequest(_ answer: String) -> Bool {
        let lowercased = answer.lowercased()
        let detailRequests = [
            "what ", "which ", "describe", "tell me", "detail",
            "symptom", "condition", "observe", "happening",
        ]
        let procedures = [
            "bandage", "boil", "clear the exhaust", "disconnect",
            "filter the water", "jack up", "jump start", "remove the",
            "replace", "splint", "start the engine", "tourniquet", "tow",
        ]
        return answer.contains("?")
            && detailRequests.contains(where: lowercased.contains)
            && !procedures.contains(where: lowercased.contains)
    }

    private static func isIncidentIntakeRequest(_ answer: String) -> Bool {
        let lowercased = answer.lowercased()
        let detailRequests = [
            "describe", "detail", "happening", "location", "observe",
            "situation", "tell me", "what ", "where ",
        ]
        let inventedActions = [
            "apply pressure", "call emergency", "check the battery", "drink water",
            "establish a secure", "move away", "secure the perimeter", "stay put",
            "turn off", "use a tourniquet",
        ]
        return detailRequests.contains(where: lowercased.contains)
            && !inventedActions.contains(where: lowercased.contains)
    }

    private static func stepMap(
        for evidence: [RetrievedPassage]
    ) -> [String: String] {
        var result: [String: String] = [:]
        for passage in evidence {
            for (index, step) in passage.article.steps.enumerated() {
                result["\(passage.article.id)#step-\(index + 1)"] = step
            }
        }
        return result
    }

    private static func approvedWarnings(
        for procedureID: String?,
        evidence: [RetrievedPassage]
    ) -> [String] {
        guard let procedureID,
              let article = evidence
                .map(\.article)
                .first(where: { $0.id == procedureID })
        else {
            return []
        }
        return article.warnings
    }

    private static func approvedSteps(
        for procedureID: String?,
        evidence: [RetrievedPassage]
    ) -> [String] {
        guard let procedureID,
              let article = evidence
                .map(\.article)
                .first(where: { $0.id == procedureID })
        else {
            return []
        }
        return article.steps
    }

    private static func render(
        _ response: GroundedResponse,
        approvedSteps: [String],
        approvedWarnings: [String]
    ) -> String {
        var sections: [String] = []
        sections.append(immediateActionText(response.immediateAction.kind))

        if !response.observations.isEmpty {
            let observations = response.observations.map {
                let percent = Int(($0.confidence * 100).rounded())
                return "• Observation (\($0.source.rawValue), \(percent)%): \($0.fact)"
            }
            sections.append(observations.joined(separator: "\n"))
        }

        if !approvedSteps.isEmpty {
            let renderedSteps = approvedSteps.enumerated().map { index, text in
                return "\(index + 1). \(text)"
            }
            sections.append(renderedSteps.joined(separator: "\n"))
        }

        let warnings = approvedWarnings + response.doNotDo.filter {
            !approvedWarnings.contains($0)
        }
        if !warnings.isEmpty {
            sections.append(
                "Do not:\n" + warnings.map { "• \($0)" }.joined(separator: "\n")
            )
        }

        if !response.questions.isEmpty {
            sections.append(
                "Check next:\n"
                    + response.questions.map { "• \($0.text)" }.joined(separator: "\n")
            )
        }

        sections.append("Driveability: \(driveabilityText(response.driveability))")
        sections.append(escalationText(for: response))
        return sections.joined(separator: "\n\n")
    }

    private static func immediateActionText(_ kind: ImmediateActionKind) -> String {
        switch kind {
        case .stop:
            return "Stop and make the scene safe before continuing."
        case .move:
            return "Move away from the immediate hazard if it is safe to do so."
        case .sos:
            return "Use Emergency SOS or contact local emergency services now."
        case .assess:
            return "Pause and assess the scene before taking another action."
        case .continue:
            return "Continue only with the cited reviewed procedure."
        }
    }

    private static func driveabilityText(_ value: Driveability) -> String {
        switch value {
        case .doNotDrive: return "Do not drive."
        case .unknown: return "Unknown; do not assume the vehicle is safe to drive."
        case .conditional: return "Conditional on the cited procedure and exact vehicle guidance."
        case .notApplicable: return "Not applicable."
        }
    }

    private static func escalationText(for response: GroundedResponse) -> String {
        switch response.riskLevel {
        case .critical, .high:
            switch response.domain {
            case .firstAid:
                return "Escalation: contact emergency medical help now."
            case .vehicle:
                return "Escalation: contact emergency or qualified roadside help now."
            case .wilderness, .navigation:
                return "Escalation: contact emergency or rescue help now."
            }
        case .moderate:
            return "Escalation: stop if conditions worsen or the reviewed procedure no longer matches."
        case .low:
            return "Escalation: seek qualified help if uncertainty remains."
        }
    }
}

private struct CompactConversationalDecision: Decodable {
    let answer: String
    let evidenceIndexes: [Int]
    let procedureIndex: Int?
    let followUp: String?

    private enum CodingKeys: String, CodingKey {
        case answer = "a"
        case evidenceIndexes = "e"
        case procedureIndex = "p"
        case followUp = "q"
    }
}

private struct CompactGroundedDecision: Decodable {
    let domain: KnowledgeDomain
    let procedureIndex: Int?

    private enum CodingKeys: String, CodingKey {
        case domain = "d"
        case procedureIndex = "p"
    }

    func expanded(
        evidence: [RetrievedPassage]
    ) throws -> GroundedResponse {
        let procedureID: String?
        if let procedureIndex {
            let offset = procedureIndex - 1
            guard evidence.indices.contains(offset) else {
                throw GroundedResponseError.unknownEvidenceIndex(
                    procedureIndex
                )
            }
            procedureID = evidence[offset].article.id
        } else {
            procedureID = nil
        }
        return GroundedResponse(
            domain: domain,
            riskLevel: procedureID == nil ? .moderate : .low,
            immediateAction: GroundedAction(
                kind: procedureID == nil ? .assess : .continue,
                evidenceIDs: procedureID.map { [$0] } ?? []
            ),
            questions: [],
            observations: [],
            procedureID: procedureID,
            steps: [],
            doNotDo: [],
            driveability: domain == .vehicle ? .unknown : .notApplicable,
            escalation: GroundedEscalation(reason: "", action: ""),
            answerConfidence: procedureID == nil ? .insufficient : .limited
        )
    }
}
