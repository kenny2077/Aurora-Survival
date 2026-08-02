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
        evidence: [RetrievedPassage]
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

        let answer = decision.answer.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !answer.isEmpty, answer.count <= 220 else {
            throw GroundedResponseError.invalidConversationalAnswer
        }
        let followUp = decision.followUp?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let followUp, followUp.isEmpty || followUp.count > 96 {
            throw GroundedResponseError.invalidFollowUp
        }

        let indexes = Self.unique(decision.evidenceIndexes)
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
        var sections: [String] = []
        let markers = response.evidenceIDs.compactMap { evidenceID in
            evidence.firstIndex(where: { $0.article.id == evidenceID })
                .map { "[\($0 + 1)]" }
        }
        sections.append(
            markers.isEmpty
                ? response.answer
                : "\(response.answer) \(markers.joined(separator: " "))"
        )

        if let procedureID = response.procedureID,
           let article = evidence
            .map(\.article)
            .first(where: { $0.id == procedureID }) {
            if !article.steps.isEmpty {
                sections.append(
                    "Reviewed procedure\n" + article.steps.enumerated()
                        .map { "\($0.offset + 1). \($0.element)" }
                        .joined(separator: "\n")
                )
            }
            if !article.warnings.isEmpty {
                sections.append(
                    "Avoid\n" + article.warnings
                        .map { "• \($0)" }
                        .joined(separator: "\n")
                )
            }
        }

        if let followUp = response.followUp {
            sections.append(followUp)
        }
        return sections.joined(separator: "\n\n")
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

    private static func unique(_ values: [Int]) -> [Int] {
        var seen: Set<Int> = []
        return values.filter { seen.insert($0).inserted }
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
