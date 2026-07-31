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

    public func decodeAndValidate(
        _ generated: String,
        evidence: [RetrievedPassage]
    ) throws -> GroundedResponse {
        guard let json = Self.jsonObjectData(in: generated) else {
            throw GroundedResponseCodecError.noJSONObject
        }
        let response: GroundedResponse
        do {
            response = try JSONDecoder().decode(GroundedResponse.self, from: json)
        } catch {
            throw GroundedResponseCodecError.invalidJSON
        }

        let evidenceIDs = Set(evidence.map(\.article.id))
        let procedureIDs = evidenceIDs
        let stepMap = Self.stepMap(for: evidence)
        let warnings = Set(evidence.flatMap(\.article.warnings))
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
        sections.append(escalationText(for: response.riskLevel))
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

    private static func escalationText(for risk: GroundedRiskLevel) -> String {
        switch risk {
        case .critical, .high:
            return "Escalation: seek qualified emergency, medical, rescue, or mechanical help now."
        case .moderate:
            return "Escalation: stop if conditions worsen or the reviewed procedure no longer matches."
        case .low:
            return "Escalation: seek qualified help if uncertainty remains."
        }
    }
}
