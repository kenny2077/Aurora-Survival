import Foundation

public struct SafetyEngine: Sendable {
    private struct Rule: Sendable {
        let terms: [String]
        let directive: SafetyDirective
    }

    private let rules: [Rule]

    public init() {
        rules = [
            Rule(
                terms: ["unconscious", "not breathing", "stopped breathing", "no pulse"],
                directive: SafetyDirective(
                    severity: .critical,
                    title: "Life-threatening emergency",
                    immediateActions: [
                        "Use Emergency SOS or call the local emergency number now.",
                        "If the person is not breathing normally, begin CPR if you are able.",
                        "Send another person to find an AED and professional help."
                    ],
                    prohibitedActions: [
                        "Do not delay emergency contact to continue chatting.",
                        "Do not give food, drink, or medication to an unconscious person."
                    ],
                    rationale: "Loss of consciousness or abnormal breathing requires immediate professional response."
                )
            ),
            Rule(
                terms: ["severe bleeding", "spurting blood", "bleeding won't stop", "bleeding wont stop"],
                directive: SafetyDirective(
                    severity: .critical,
                    title: "Severe bleeding",
                    immediateActions: [
                        "Use Emergency SOS or call the local emergency number now.",
                        "Apply firm, continuous direct pressure with cloth or gauze.",
                        "Keep the person warm and still while help is arranged."
                    ],
                    prohibitedActions: [
                        "Do not repeatedly lift the dressing to check the wound.",
                        "Do not remove an embedded object."
                    ],
                    rationale: "Uncontrolled bleeding can become fatal within minutes."
                )
            ),
            Rule(
                terms: ["fuel leak", "smell gasoline", "smell gas", "vehicle fire", "car fire", "smoke from engine"],
                directive: SafetyDirective(
                    severity: .critical,
                    title: "Fire or fuel hazard",
                    immediateActions: [
                        "Turn off the ignition only if you can do so without approaching flames.",
                        "Move everyone at least 30 metres (100 feet) away and stay upwind.",
                        "Use Emergency SOS or contact emergency services."
                    ],
                    prohibitedActions: [
                        "Do not restart the engine.",
                        "Do not smoke, create sparks, or open a hot pressurized system.",
                        "Do not return to the vehicle for belongings."
                    ],
                    rationale: "Fuel vapour, battery damage, or an engine-compartment fire can ignite or explode."
                )
            ),
            Rule(
                terms: ["carbon monoxide", "running engine in garage", "engine in enclosed"],
                directive: SafetyDirective(
                    severity: .critical,
                    title: "Possible carbon monoxide exposure",
                    immediateActions: [
                        "Move everyone into fresh air immediately.",
                        "Turn off the engine only if it is safe to do so from fresh air.",
                        "Use Emergency SOS or contact emergency services."
                    ],
                    prohibitedActions: [
                        "Do not re-enter the enclosed space.",
                        "Do not rely on smell to judge whether the area is safe."
                    ],
                    rationale: "Carbon monoxide is invisible, has no reliable warning odour, and can rapidly incapacitate."
                )
            ),
            Rule(
                terms: ["chest pain", "signs of stroke", "face drooping", "slurred speech", "anaphylaxis"],
                directive: SafetyDirective(
                    severity: .critical,
                    title: "Time-critical medical symptoms",
                    immediateActions: [
                        "Use Emergency SOS or call the local emergency number now.",
                        "Keep the person resting, warm, and under observation.",
                        "Follow instructions from the emergency dispatcher."
                    ],
                    prohibitedActions: [
                        "Do not drive if symptoms make driving unsafe.",
                        "Do not give unprescribed medication."
                    ],
                    rationale: "These symptoms can indicate a condition where treatment delay changes the outcome."
                )
            )
        ]
    }

    public func evaluate(_ text: String) -> SafetyDirective? {
        let normalized = Self.normalize(text)
        return rules
            .filter { rule in rule.terms.contains(where: normalized.contains) }
            .map(\.directive)
            .max { $0.severity < $1.severity }
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
    }
}
