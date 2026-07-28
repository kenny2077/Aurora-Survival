import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var preferredTier: ModelTier = .essential {
        didSet { persistPreparation() }
    }
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false
    @Published var attachedImageData: Data?
    @Published var imageObservations: [String] = []
    @Published var libraryQuery = ""
    @Published var readinessChecks: [ReadinessCheck] = ReadinessCheck.defaults
    @Published var vehicleProfile: VehicleProfile?
    @Published private(set) var emergencyCoreStatus = "Emergency core unavailable"
    @Published private(set) var activePackStatus = "Active packages not checked"
    @Published private(set) var activePackIssueCount = 0
    @Published private(set) var runtimeTiers: Set<ModelTier> = [.essential]
    @Published var incidentModeEnabled = true

    let articles: [KnowledgeArticle]
    let entitlementLedger: EntitlementLedger
    private var assistant: IncidentAssistant
    private let appDataRoot: URL
    private let policyVersion: String
    private let preparationStore: PreparationStateStore
    private let deviceProfiler = DeviceProfiler()
    private let ocr = VisionTextExtractor()
    private var isRefreshingActivePacks = false

    init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let appDataRoot = applicationSupport.appendingPathComponent(
            "TrailGuard",
            isDirectory: true
        )
        self.appDataRoot = appDataRoot
        entitlementLedger = EntitlementLedger(
            fileURL: appDataRoot.appendingPathComponent("entitlements.json")
        )
        preparationStore = PreparationStateStore(
            fileURL: appDataRoot.appendingPathComponent("preparation-state.json")
        )

        let loaded: [KnowledgeArticle]
        let coreStatus: String
        let corePolicyVersion: String
        if let url = Bundle.main.url(
            forResource: "emergency_core",
            withExtension: "json"
        ),
           let bundledData = try? Data(contentsOf: url),
           let result = try? EmergencyCoreStore(
               rootDirectory: appDataRoot,
               bundledData: bundledData
           ).loadOrRecover() {
            loaded = result.bundle.articles
            corePolicyVersion = result.bundle.policyVersion
            switch result.origin {
            case .active:
                coreStatus = "Verified emergency core \(result.bundle.version)"
            case .bundledFirstLaunch:
                coreStatus = "Bundled emergency core installed"
            case .bundledRecovery:
                coreStatus = "Emergency core recovered from bundled copy"
            }
        } else if let url = Bundle.main.url(
            forResource: "starter_knowledge",
            withExtension: "json"
        ),
                  let store = try? KnowledgeStore.load(url: url) {
            loaded = store.articles
            coreStatus = "Legacy bundled guide loaded"
            corePolicyVersion = "deterministic-policy-v1"
        } else {
            loaded = []
            coreStatus = "Emergency core unavailable"
            corePolicyVersion = "deterministic-policy-v1"
        }
        articles = loaded
        policyVersion = corePolicyVersion

        // Essential is ready immediately. Optional packages are revalidated
        // asynchronously before a replacement assistant can use them.
        assistant = IncidentAssistant(
            articles: loaded,
            installedTiers: [.essential]
        )
        emergencyCoreStatus = coreStatus

        if let state = try? preparationStore.load() {
            vehicleProfile = state.vehicleProfile
            preferredTier = state.preferredTier
            readinessChecks = ReadinessCheck.defaults.map { check in
                var restored = check
                restored.isComplete = check.id == "knowledge"
                    || state.completedReadinessIDs.contains(check.id)
                return restored
            }
            if state.vehicleProfile != nil,
               let index = readinessChecks.firstIndex(where: {
                   $0.id == "vehicle"
               }) {
                readinessChecks[index].isComplete = true
            }
        }
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

    var installedTierSummary: String {
        let names = ModelTier.allCases
            .filter(runtimeTiers.contains)
            .map(\.displayName)
            .joined(separator: ", ")
        return "\(names) active · optional tiers require a verified package and runtime"
    }

    func refreshActivePacks() async {
        guard !isRefreshingActivePacks else { return }
        isRefreshingActivePacks = true
        defer { isRefreshingActivePacks = false }

        let verifier = PackageVerifier(
            trustedKeys: Self.loadTrustedPackageKeys()
        )
        let registry = ActivePackRegistry(
            rootDirectory: appDataRoot,
            verifier: verifier,
            appVersion: Self.appVersion,
            expectedPolicyVersion: policyVersion
        )
        let snapshot = await registry.resolve(
            cachedEntitlements: await entitlementLedger.snapshots(),
            device: deviceProfiler.snapshot()
        )
        let runtime = IncidentRuntimeBootstrap(
            bundledArticles: articles
        ).resolve(
            activePacks: snapshot,
            availableModelTiers: [.essential]
        )

        assistant = runtime.assistant
        runtimeTiers = runtime.runtimeTiers
        activePackIssueCount = snapshot.issues.count + runtime.issues.count
        if activePackIssueCount > 0 {
            activePackStatus = "Essential fallback active · \(activePackIssueCount) package issue(s)"
        } else if runtime.usesCompiledKnowledge {
            activePackStatus = "Verified compiled knowledge active"
        } else if snapshot.models.isEmpty && snapshot.maps.isEmpty {
            activePackStatus = "No verified optional packs · Essential ready"
        } else {
            activePackStatus = "Verified optional packs checked · unavailable runtimes stay disabled"
        }
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
        persistPreparation()
    }

    func saveVehicle(_ profile: VehicleProfile) {
        guard profile.isPlausible else { return }
        vehicleProfile = profile
        if let index = readinessChecks.firstIndex(where: { $0.id == "vehicle" }) {
            readinessChecks[index].isComplete = true
        }
        persistPreparation()
    }

    func removeVehicle() {
        vehicleProfile = nil
        if let index = readinessChecks.firstIndex(where: { $0.id == "vehicle" }) {
            readinessChecks[index].isComplete = false
        }
        persistPreparation()
    }

    private func persistPreparation() {
        let completed = Set(
            readinessChecks
                .filter(\.isComplete)
                .map(\.id)
        )
        try? preparationStore.save(
            PreparationState(
                vehicleProfile: vehicleProfile,
                completedReadinessIDs: completed,
                preferredTier: preferredTier
            )
        )
    }

    private static var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
    }

    private static func loadTrustedPackageKeys() -> [TrustedPackageKey] {
        guard let url = Bundle.main.url(
            forResource: "trusted_package_keys",
            withExtension: "json"
        ),
              let data = try? Data(contentsOf: url),
              let keys = try? JSONDecoder().decode(
                  [TrustedPackageKey].self,
                  from: data
              )
        else { return [] }
        return keys
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
