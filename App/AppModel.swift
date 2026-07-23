import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var preferredTier: ModelTier = .essential
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false
    @Published var attachedImageData: Data?
    @Published var imageObservations: [String] = []
    @Published var libraryQuery = ""
    @Published var readinessChecks: [ReadinessCheck] = ReadinessCheck.defaults
    @Published var vehicleProfile: VehicleProfile?

    let articles: [KnowledgeArticle]
    private let assistant: IncidentAssistant
    private let deviceProfiler = DeviceProfiler()
    private let ocr = VisionTextExtractor()

    init() {
        let loaded: [KnowledgeArticle]
        if let url = Bundle.main.url(forResource: "starter_knowledge", withExtension: "json"),
           let store = try? KnowledgeStore.load(url: url) {
            loaded = store.articles
        } else {
            loaded = []
        }
        articles = loaded

        // Model package installation is intentionally explicit. Essential is the
        // safe extractive fallback included in the binary.
        assistant = IncidentAssistant(
            articles: loaded,
            installedTiers: [.essential]
        )
    }

    var filteredArticles: [KnowledgeArticle] {
        guard !libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return articles
        }
        let terms = libraryQuery.lowercased()
        return articles.filter { $0.searchableText.lowercased().contains(terms) }
    }

    var readinessProgress: Double {
        guard !readinessChecks.isEmpty else { return 0 }
        return Double(readinessChecks.filter(\.isComplete).count) / Double(readinessChecks.count)
    }

    func attachImage(data: Data) async {
        attachedImageData = data
        imageObservations = await ocr.extractText(from: data)
    }

    func removeAttachment() {
        attachedImageData = nil
        imageObservations = []
    }

    func send(_ question: String, domain: KnowledgeDomain? = nil) async {
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isThinking else { return }

        messages.append(ChatMessage(role: .user, text: clean, answer: nil))
        isThinking = true
        defer {
            isThinking = false
            removeAttachment()
        }

        let request = ChatRequest(
            question: clean,
            domain: domain,
            preferredTier: preferredTier,
            hasImage: attachedImageData != nil,
            imageData: attachedImageData,
            imageObservations: imageObservations,
            vehicleProfile: vehicleProfile
        )
        let answer = await assistant.answer(
            request: request,
            device: deviceProfiler.snapshot()
        )
        messages.append(ChatMessage(role: .assistant, text: answer.text, answer: answer))
    }

    func resetConversation() {
        messages = []
        removeAttachment()
    }

    func toggleReadiness(_ id: String) {
        guard let index = readinessChecks.firstIndex(where: { $0.id == id }) else { return }
        readinessChecks[index].isComplete.toggle()
    }

    func saveVehicle(_ profile: VehicleProfile) {
        guard profile.isPlausible else { return }
        vehicleProfile = profile
        if let index = readinessChecks.firstIndex(where: { $0.id == "vehicle" }) {
            readinessChecks[index].isComplete = true
        }
    }

    func removeVehicle() {
        vehicleProfile = nil
    }
}

struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    let answer: AssistantAnswer?
}

struct ReadinessCheck: Identifiable {
    let id: String
    let title: String
    let detail: String
    var isComplete: Bool

    static let defaults = [
        ReadinessCheck(
            id: "power",
            title: "Power reserve",
            detail: "Phone charged; cable and power bank packed.",
            isComplete: false
        ),
        ReadinessCheck(
            id: "knowledge",
            title: "Knowledge pack",
            detail: "Starter vehicle, first-aid, and wilderness guidance opens in Airplane Mode.",
            isComplete: true
        ),
        ReadinessCheck(
            id: "map",
            title: "Offline map",
            detail: "Destination region downloaded and route previewed.",
            isComplete: false
        ),
        ReadinessCheck(
            id: "contacts",
            title: "Trip contact",
            detail: "A trusted person has route, vehicle, party, and return time.",
            isComplete: false
        ),
        ReadinessCheck(
            id: "vehicle",
            title: "Vehicle essentials",
            detail: "Owner manual, spare, jack, tools, water, and warning equipment checked.",
            isComplete: false
        )
    ]
}
