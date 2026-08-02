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
    @Published private(set) var lastModelMetrics: LlamaCompletionMetrics?
    @Published private(set) var lastModelThermalCondition: ThermalCondition?
    @Published var incidentModeEnabled = true
    @Published var catalogURLString = "" {
        didSet {
            UserDefaults.standard.set(
                catalogURLString,
                forKey: Self.catalogURLDefaultsKey
            )
        }
    }
    @Published private(set) var catalogEntries: [PackageCatalogEntry] = []
    @Published private(set) var packageDownloadStates: [
        String: PackageDownloadState
    ] = [:]
    @Published private(set) var catalogStatus = "Connect to a signed package catalog."
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var offlineMaps: [ResolvedOfflineMap] = []

    let articles: [KnowledgeArticle]
    let entitlementLedger: EntitlementLedger
    private var assistant: IncidentAssistant
    private let appDataRoot: URL
    private let policyVersion: String
    private let preparationStore: PreparationStateStore
    private let deviceProfiler = DeviceProfiler()
    private let ocr = VisionTextExtractor()
    private var isRefreshingActivePacks = false
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private lazy var packageInstaller = PackageInstaller(
        rootDirectory: appDataRoot,
        verifier: PackageVerifier(
            trustedKeys: Self.loadTrustedPackageKeys()
        )
    )

    init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let appDataRoot = applicationSupport.appendingPathComponent(
            "Aurora",
            isDirectory: true
        )
        self.appDataRoot = appDataRoot
        let developmentCatalogURL = Self.developmentCatalogURL
        catalogURLString = developmentCatalogURL.isEmpty
            ? UserDefaults.standard.string(
                forKey: Self.catalogURLDefaultsKey
            ) ?? ""
            : developmentCatalogURL
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
            case .bundledUpgrade:
                coreStatus = "Bundled emergency core upgraded to \(result.bundle.version)"
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

    var lastModelMetricsSummary: String {
        guard let metrics = lastModelMetrics else {
            return "No native model run recorded"
        }
        let firstTokenSeconds = Double(metrics.firstTokenMilliseconds) / 1_000
        let temperature = lastModelThermalCondition?.rawValue ?? "unknown"
        return String(
            format: "First token %.2fs · %.1f tok/s · %d tokens · thermal %@%@",
            firstTokenSeconds,
            metrics.tokensPerSecond,
            metrics.generatedTokenCount,
            temperature,
            metrics.coldStart ? " · cold" : ""
        )
    }

    var deviceConditionSummary: String {
        let snapshot = deviceProfiler.snapshot()
        let power = snapshot.isLowPowerMode
            ? "Low Power Mode"
            : "Standard power"
        return "\(power) · thermal \(snapshot.thermalCondition.rawValue)"
    }

    func refreshCatalog() async {
        guard !isLoadingCatalog else { return }
        guard !incidentModeEnabled else {
            catalogStatus = "Switch to Preparation mode to use the network."
            return
        }
        guard let url = URL(string: catalogURLString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else {
            catalogStatus = "Enter the signed catalog URL from your Mac or production host."
            return
        }

        isLoadingCatalog = true
        catalogStatus = "Checking signatures…"
        defer { isLoadingCatalog = false }
        do {
            let data = try await URLSessionPackageTransport().data(from: url)
            let signed = try JSONDecoder().decode(
                SignedPackageCatalog.self,
                from: data
            )
            let verified = try PackageCatalogVerifier(
                trustedKeys: Self.loadTrustedPackageKeys()
            ).verify(signed)
            catalogEntries = verified.entries
            try await refreshInstalledPackageStates()
            catalogStatus = "Verified catalog · \(verified.entries.count) downloads"
        } catch {
            catalogEntries = []
            catalogStatus = "Catalog verification failed: \(Self.userMessage(for: error))"
        }
    }

    func download(_ entry: PackageCatalogEntry) async {
        guard !incidentModeEnabled else {
            packageDownloadStates[entry.id] = .failed(
                "Downloads are disabled in Incident mode."
            )
            return
        }
        guard let catalogURL = URL(string: catalogURLString) else {
            packageDownloadStates[entry.id] = .failed(
                "The catalog URL is invalid."
            )
            return
        }

        packageDownloadStates[entry.id] = .downloading(0)
        do {
            let location = try entry.remoteLocation(relativeTo: catalogURL)
            let coordinator = PackageDownloadCoordinator(
                stagingRoot: appDataRoot.appendingPathComponent(
                    "download-staging",
                    isDirectory: true
                ),
                installer: packageInstaller,
                networkPolicy: IncidentNetworkPolicy(
                    incidentModeEnabled: incidentModeEnabled
                ),
                chunkByteCount: 8 * 1_048_576
            )
            _ = try await coordinator.downloadAndInstall(
                from: location,
                expecting: PackageDownloadExpectation(
                    packageID: entry.packageID,
                    version: entry.version,
                    kind: entry.kind
                ),
                progress: { [weak self] progress in
                    self?.packageDownloadStates[entry.id] = .downloading(
                        progress.fractionCompleted
                    )
                }
            )
            try await refreshInstalledPackageStates()
            markReadinessComplete(for: entry.kind)
            await refreshActivePacks()
        } catch PackageInstallError.packageAlreadyInstalled {
            try? await refreshInstalledPackageStates()
            await refreshActivePacks()
        } catch {
            packageDownloadStates[entry.id] = .failed(
                Self.userMessage(for: error)
            )
        }
    }

    func startDownload(_ entry: PackageCatalogEntry) {
        guard downloadTasks[entry.id] == nil else { return }
        downloadTasks[entry.id] = Task { [weak self] in
            await self?.download(entry)
            self?.downloadTasks[entry.id] = nil
        }
    }

    func cancelDownload(_ entry: PackageCatalogEntry) {
        downloadTasks[entry.id]?.cancel()
    }

    func packageState(for entry: PackageCatalogEntry) -> PackageDownloadState {
        packageDownloadStates[entry.id] ?? .available
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
            expectedPolicyVersion: policyVersion,
            allowDevelopmentKnowledge: Self.allowDevelopmentKnowledge
        )
        let snapshot = await registry.resolve(
            cachedEntitlements: await entitlementLedger.snapshots(),
            device: deviceProfiler.snapshot()
        )
        let mapRuntime = OfflineMapRuntimeResolver().resolve(
            activePacks: snapshot
        )
        offlineMaps = mapRuntime.maps
        let modelRuntime = ActiveModelRuntimeResolver().resolve(
            activePacks: snapshot
        )
        var availableModelTiers: Set<ModelTier> = [.essential]
        var runtimeModels: [ModelTier: any LocalLanguageModel] = [:]
        var runtimeBindingIssueCount = modelRuntime.issues.count
#if canImport(AuroraLlamaRuntime)
        if let descriptor = modelRuntime.descriptors[.lite] {
            do {
                runtimeModels[.lite] = try LlamaLanguageModel(
                    tier: .lite,
                    configuration: .lite(
                        modelURL: descriptor.modelURL,
                        threadCount: 4
                    ),
                    backend: LlamaXCFrameworkBackend(),
                    metricsSink: { [weak self] metrics in
                        await self?.recordModelMetrics(metrics)
                    }
                )
                availableModelTiers.insert(.lite)
            } catch {
                runtimeBindingIssueCount += 1
            }
        }
#endif
        let boundRuntimeModels = runtimeModels
        let runtime = IncidentRuntimeBootstrap(
            bundledArticles: articles,
            modelProvider: { tier in
                boundRuntimeModels[tier]
                    ?? ExtractiveLanguageModel(tier: tier)
            }
        ).resolve(
            activePacks: snapshot,
            availableModelTiers: availableModelTiers
        )

        assistant = runtime.assistant
        runtimeTiers = runtime.runtimeTiers
        activePackIssueCount = snapshot.issues.count
            + runtime.issues.count
            + runtimeBindingIssueCount
            + mapRuntime.issues.count
        if activePackIssueCount > 0 {
            let activeOptionalTiers = ModelTier.allCases
                .filter { $0 != .essential && runtimeTiers.contains($0) }
                .map(\.displayName)
                .joined(separator: ", ")
            if activeOptionalTiers.isEmpty {
                activePackStatus = "Essential fallback active · \(activePackIssueCount) optional item issue(s)"
            } else {
                activePackStatus = "\(activeOptionalTiers) active · \(activePackIssueCount) optional item issue(s)"
            }
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

    func loadDebugOCRFixtureIfPresent() async {
#if DEBUG
        guard attachedImageData == nil,
              let encoded = ProcessInfo.processInfo.environment[
                  "TRAILGUARD_DEBUG_OCR_FIXTURE_BASE64"
              ],
              let data = Data(base64Encoded: encoded)
        else { return }
        await attachImage(data: data)
#endif
    }

    func removeAttachment() {
        attachedImageData = nil
        imageObservations = []
    }

    func send(_ question: String, domain: KnowledgeDomain? = nil) async {
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isThinking else { return }

        let conversationHistory = messages.suffix(6).map { message in
            ConversationTurn(
                role: message.role == .user ? .user : .assistant,
                text: message.text
            )
        }
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
            vehicleProfile: vehicleProfile,
            conversationHistory: conversationHistory
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

    private func recordModelMetrics(_ metrics: LlamaCompletionMetrics) {
        lastModelMetrics = metrics
        lastModelThermalCondition = deviceProfiler.snapshot().thermalCondition
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

    private func refreshInstalledPackageStates() async throws {
        let index = try await packageInstaller.index()
        let active = index.activeVersions
        for entry in catalogEntries {
            let installed = index.installed.contains {
                $0.packageID == entry.packageID && $0.version == entry.version
            }
            if installed {
                packageDownloadStates[entry.id] = .installed(
                    active: active[entry.packageID] == entry.version
                )
            } else if case .downloading = packageDownloadStates[entry.id] {
                continue
            } else {
                packageDownloadStates[entry.id] = .available
            }
        }
    }

    private func markReadinessComplete(for kind: PackageKind) {
        let readinessID: String?
        switch kind {
        case .knowledge:
            readinessID = "knowledge"
        case .map:
            readinessID = "map"
        case .model:
            readinessID = nil
        }
        if let readinessID,
           let index = readinessChecks.firstIndex(where: {
               $0.id == readinessID
           }) {
            readinessChecks[index].isComplete = true
            persistPreparation()
        }
    }

    private static func userMessage(for error: Error) -> String {
        switch error {
        case PackageDownloadError.incidentModeDenied:
            return "Downloads are disabled in Incident mode."
        case PackageDownloadError.unexpectedPackage:
            return "The package identity did not match the signed catalog."
        case PackageCatalogError.invalidSignature,
             PackageVerificationError.invalidSignature:
            return "The signature is invalid. Nothing was installed."
        case PackageCatalogError.unknownSigningKey,
             PackageVerificationError.unknownSigningKey:
            return "The signing key is not trusted by this build."
        case PackageInstallError.insufficientSpace:
            return "There is not enough free storage for this download."
        case is CancellationError:
            return "Paused. Start again to resume from the verified partial file."
        default:
            return error.localizedDescription
        }
    }

    private static var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
    }

    private static let catalogURLDefaultsKey = "Aurora.catalogURL"

    private static var developmentCatalogURL: String {
#if DEBUG
        ProcessInfo.processInfo.environment["TRAILGUARD_CATALOG_URL"] ?? ""
#else
        ""
#endif
    }

    private static func loadTrustedPackageKeys() -> [TrustedPackageKey] {
        var keys = loadTrustedPackageKeys(
            resource: "trusted_package_keys"
        )
#if DEBUG
        keys.append(contentsOf: loadTrustedPackageKeys(
            resource: "development_trusted_package_keys"
        ))
#endif
        return keys
    }

    private static func loadTrustedPackageKeys(
        resource: String
    ) -> [TrustedPackageKey] {
        guard let url = Bundle.main.url(
            forResource: resource,
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

    private static var allowDevelopmentKnowledge: Bool {
#if DEBUG
        true
#else
        false
#endif
    }
}

enum PackageDownloadState: Equatable {
    case available
    case downloading(Double)
    case installed(active: Bool)
    case failed(String)
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
