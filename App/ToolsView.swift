import CoreLocation
import SwiftUI

struct ToolsView: View {
    private enum ToolRoute: Hashable {
        case flashlight
        case satellite
        case compass
        case checklist
    }

    @EnvironmentObject private var model: AppModel
    @StateObject private var emergencyStore = EmergencyProfileStore()
    @StateObject private var checklistStore = TripChecklistStore()
    @StateObject private var locationModel = SurvivalToolsLocationModel()
    @StateObject private var flashlight = SOSFlashlightController()
    @State private var showsSettings = false
    @State private var modelPendingRemoval: ModelTier?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AuroraDesign.Space.lg) {
                emergencyHero
                offlineAI
                Text("Field tools").font(.title2.bold())
                GlassEffectContainer(spacing: AuroraDesign.Space.sm) {
                    LazyVGrid(columns: columns, spacing: AuroraDesign.Space.sm) {
                        toolLink("SOS Flashlight", flashlight.isRunning ? "SIGNALING" : "Morse torch signal", "flashlight.on.fill", .orange, route: .flashlight)
                        toolLink("Satellite", "Compatibility & guide", "antenna.radiowaves.left.and.right", .indigo, route: .satellite)
                        toolLink("Compass", "Heading & coordinates", "safari.fill", AuroraDesign.river, route: .compass)
                        toolLink("Checklist", "\(checklistStore.completedCount) of \(checklistStore.items.count) ready", "checklist.checked", .green, route: .checklist)
                    }
                }
            }
            .padding(AuroraDesign.Space.md)
            .frame(maxWidth: AuroraDesign.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [.init(uiColor: .systemGroupedBackground), AuroraDesign.river.opacity(0.08), .indigo.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()
        )
        .navigationTitle("Tools")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsSettings = true } label: { Image(systemName: "gearshape.fill") }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Tools settings")
                    .accessibilityIdentifier("tools.settings")
            }
        }
        .task { await model.ensureCatalogLoaded() }
        .sheet(isPresented: $showsSettings) {
            ToolsSettingsView(model: model, checklistStore: checklistStore)
                .presentationBackground(.ultraThinMaterial)
        }
        .confirmationDialog(
            "Remove \(modelPendingRemoval?.displayName ?? "model") download?",
            isPresented: Binding(
                get: { modelPendingRemoval != nil },
                set: { if !$0 { modelPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let tier = modelPendingRemoval {
                Button("Remove \(tier.displayName)", role: .destructive) {
                    model.removeModelSetup(tier)
                    modelPendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) { modelPendingRemoval = nil }
        } message: {
            Text("The shared survival knowledge is preserved while another AI tier needs it, and removed only with the final tier.")
        }
        .navigationDestination(for: ToolRoute.self) { route in
            toolDestination(for: route)
        }
        .accessibilityIdentifier("tools.home")
    }

    private var emergencyHero: some View {
        NavigationLink {
            EmergencyCenterView(store: emergencyStore, location: locationModel)
        } label: {
            HStack(spacing: AuroraDesign.Space.sm) {
                Image(systemName: "sos.circle.fill")
                    .font(.title2)
                Spacer()
                Text("Emergency Center")
                    .font(.headline)
                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AuroraDesign.Space.md)
            .padding(.vertical, AuroraDesign.Space.sm)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [AuroraDesign.signal, .red.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .shadow(color: AuroraDesign.signal.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tools.emergency")
    }

    private var offlineAI: some View {
        VStack(alignment: .leading, spacing: AuroraDesign.Space.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Offline AI").font(.title2.bold())
                    Text(model.loadedTier.map { "\($0.displayName) loaded" } ?? "No model loaded this launch")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                modelMenu
            }
            tierCard(.lite)
            tierCard(.expert)
        }
        .padding(AuroraDesign.Space.md)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityIdentifier("tools.offlineAI")
    }

    private var modelMenu: some View {
        Menu {
            ForEach(ModelTier.allCases, id: \.self) { tier in
                Button { choose(tier) } label: {
                    Label(model.loadedTier == tier ? "\(tier.displayName) loaded" : "Load \(tier.displayName)",
                          systemImage: model.loadedTier == tier ? "checkmark" : "cpu")
                }
            }
        } label: {
            Label(model.modelSelection.displayName, systemImage: "chevron.up.chevron.down")
                .font(.subheadline.bold())
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("tools.modelSelection")
    }

    private func choose(_ tier: ModelTier) {
        model.modelSelection = tier == .lite ? .lite : .expert
        guard model.runtimeTiers.contains(tier) else { return }
        Task { await model.loadModel(tier) }
    }

    private func tierCard(_ tier: ModelTier) -> some View {
        VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
            HStack(alignment: .top) {
                Image(systemName: tier == .lite ? "text.bubble.fill" : "eye.fill")
                    .font(.title2).foregroundStyle(tier == .lite ? AuroraDesign.river : .indigo)
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(tier.displayName).font(.headline)
                    Text(tier == .lite ? "Fast · text" : "Advanced · text + vision")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                }
                Spacer()
                modelStatus(tier)
                if case .ready = model.modelSetupState(for: tier) {
                    Menu {
                        Button("Remove Download", role: .destructive) {
                            modelPendingRemoval = tier
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Manage \(tier.displayName) download")
                }
            }
            Text(tier == .lite
                 ? "Lower-memory offline guidance paired with Aurora’s reviewed survival knowledge and embedding index."
                 : "Higher-depth offline guidance with photo analysis on validated high-memory devices.")
                .font(.caption).foregroundStyle(.secondary)
            modelAction(tier)
        }
        .padding(AuroraDesign.Space.md)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("tools.tier.\(tier.rawValue)")
    }

    private func modelStatus(_ tier: ModelTier) -> some View {
        let result: (String, Color)
        if model.loadedTier == tier {
            result = ("LOADED", .green)
        } else {
            result = switch model.modelSetupState(for: tier) {
            case .ready: ("READY", .green)
            case .downloading: ("DOWNLOADING", .blue)
            case .available: ("AVAILABLE", .blue)
            case .failed: ("ATTENTION", .red)
            case .unavailable: ("UNAVAILABLE", .secondary)
            }
        }
        return Text(result.0).font(.caption2.bold()).foregroundStyle(result.1)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(result.1.opacity(0.12), in: Capsule())
    }

    @ViewBuilder private func modelAction(_ tier: ModelTier) -> some View {
        if case .loading(tier) = model.modelRuntimeState {
            HStack { ProgressView(); Text("Loading \(tier.displayName)…") }.font(.subheadline.bold())
        } else if model.loadedTier == tier {
            Label("Loaded for this launch", systemImage: "checkmark.circle.fill")
                .font(.subheadline.bold()).foregroundStyle(.green)
        } else {
            switch model.modelSetupState(for: tier) {
            case .ready:
                Button { Task { await model.loadModel(tier) } } label: {
                    Label("Load \(tier.displayName)", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.glassProminent)
            case let .downloading(fraction):
                ProgressView(value: fraction) { Text("Preparing \(fraction.formatted(.percent.precision(.fractionLength(0))))") }
                Button("Pause") { model.cancelModelSetup(tier) }.buttonStyle(.glass)
            case .available:
                Button { model.startModelSetup(tier) } label: {
                    Label(downloadLabel(tier), systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.glassProminent)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
                Button("Try Again") { model.startModelSetup(tier) }.buttonStyle(.glassProminent)
            case .unavailable:
                Text(model.catalogStatus).font(.caption).foregroundStyle(.secondary)
                Button("Check Availability") { Task { await model.refreshCatalog() } }.buttonStyle(.glass)
            }
        }
    }

    private func downloadLabel(_ tier: ModelTier) -> String {
        let bytes = model.modelSetupByteCount(for: tier)
        let base = "Download \(tier.displayName) + Knowledge"
        return bytes > 0 ? base + " · " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : base
    }

    private func toolLink(_ title: String, _ detail: String, _ symbol: String,
                          _ tint: Color, route: ToolRoute) -> some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
                Image(systemName: symbol).font(.title2).foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 13))
                Spacer(minLength: 6)
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(AuroraDesign.Space.md)
            .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 22))
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func toolDestination(for route: ToolRoute) -> some View {
        switch route {
        case .flashlight:
            SOSFlashlightView(controller: flashlight)
        case .satellite:
            SatelliteGuideView()
        case .compass:
            CompassToolView(location: locationModel)
        case .checklist:
            TripChecklistView(store: checklistStore)
        }
    }
}

private struct EmergencyCenterView: View {
    @ObservedObject var store: EmergencyProfileStore
    @ObservedObject var location: SurvivalToolsLocationModel
    @State private var editsProfile = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AuroraDesign.Space.lg) {
                coordinatesCard
                contactsCard
                medicalCard
                sosInstructions
            }.padding().frame(maxWidth: AuroraDesign.readableWidth).frame(maxWidth: .infinity)
        }
        .navigationTitle("Emergency Center")
        .toolbar { Button("Edit") { editsProfile = true }.buttonStyle(.glass) }
        .onAppear { location.start() }
        .onDisappear { location.stop() }
        .sheet(isPresented: $editsProfile) { EmergencyProfileEditor(store: store) }
        .accessibilityIdentifier("tools.emergency.center")
    }

    private var coordinatesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Current coordinates", systemImage: "location.fill").font(.headline)
            if let fix = location.latestFix {
                Text(coordinateText(fix)).font(.title3.monospaced().bold()).textSelection(.enabled)
                Text("Accuracy ±\(Int(max(0, fix.horizontalAccuracy))) m · \(fix.timestamp.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Copy") { UIPasteboard.general.string = coordinateText(fix) }.buttonStyle(.glass)
                    ShareLink(item: coordinateText(fix)) { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(.glass)
                }
            } else if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                Label("Location access is off. Enable it in Settings to show coordinates.", systemImage: "location.slash.fill")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Finding your location…")
            }
        }.toolCard()
    }

    private var contactsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Emergency contacts", systemImage: "person.2.fill").font(.headline)
            if store.profile.contacts.isEmpty {
                Text("Add the people responders or companions should contact.").foregroundStyle(.secondary)
            } else {
                ForEach(store.profile.contacts) { contact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name).font(.subheadline.bold())
                        Text([contact.relationship, contact.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.toolCard()
    }

    private var medicalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Medical information", systemImage: "medical.thermometer.fill").font(.headline)
            medicalRow("Blood type", store.profile.bloodType)
            medicalRow("Allergies", store.profile.allergies)
            medicalRow("Conditions", store.profile.conditions)
            medicalRow("Medications", store.profile.medications)
            medicalRow("Notes", store.profile.notes)
            if [store.profile.bloodType, store.profile.allergies, store.profile.conditions,
                store.profile.medications, store.profile.notes].allSatisfy(\.isEmpty) {
                Text("Add essential details that may help responders.").foregroundStyle(.secondary)
            }
        }.toolCard()
    }

    private var sosInstructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Make an emergency call on iPhone", systemImage: "sos").font(.headline)
            Text("1. Press and hold the side button and either Volume button together until the Emergency Call slider appears.")
            Text("2. Drag the Emergency Call slider to call emergency services.")
        }.font(.subheadline).toolCard()
    }

    private func coordinateText(_ fix: LocationFix) -> String {
        String(format: "%.6f, %.6f", fix.coordinate.latitude, fix.coordinate.longitude)
    }

    @ViewBuilder private func medicalRow(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold()).foregroundStyle(.secondary)
                Text(value).font(.subheadline)
            }
        }
    }
}

private struct EmergencyProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: EmergencyProfileStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Emergency contacts") {
                    ForEach($store.profile.contacts) { $contact in
                        TextField("Name", text: $contact.name)
                        TextField("Relationship", text: $contact.relationship)
                        TextField("Phone", text: $contact.phone).keyboardType(.phonePad)
                    }.onDelete { store.profile.contacts.remove(atOffsets: $0) }
                    Button("Add Contact") { store.profile.contacts.append(EmergencyContact()) }
                }
                Section("Medical information") {
                    TextField("Blood type", text: $store.profile.bloodType)
                    TextField("Allergies", text: $store.profile.allergies, axis: .vertical)
                    TextField("Conditions", text: $store.profile.conditions, axis: .vertical)
                    TextField("Medications", text: $store.profile.medications, axis: .vertical)
                    TextField("Notes", text: $store.profile.notes, axis: .vertical)
                }
                Section {
                    Text("Stored only on this device with iOS file protection. Aurora does not transmit this profile.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let message = store.errorMessage { Text(message).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Emergency Information")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.save(); dismiss() } }
            }
        }
    }
}

private struct SOSFlashlightView: View {
    @ObservedObject var controller: SOSFlashlightController
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: AuroraDesign.Space.xl) {
            Spacer()
            Image(systemName: controller.isRunning ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(controller.isRunning ? .orange : .secondary)
                .symbolEffect(.pulse, isActive: controller.isRunning)
            Text(controller.isRunning ? "SOS signal active" : "SOS Flashlight").font(.largeTitle.bold())
            Text("Repeats the international · · · — — — · · · torch pattern. This visual signal does not replace contacting emergency services.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let error = controller.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            Button(controller.isRunning ? "STOP SIGNAL" : "Start SOS Signal") {
                controller.isRunning ? controller.stop() : controller.start()
            }
            .buttonStyle(.borderedProminent).tint(controller.isRunning ? .red : .orange).controlSize(.large)
            .accessibilityIdentifier("tools.flashlight.toggle")
            Spacer()
        }
        .padding(AuroraDesign.Space.lg)
        .navigationTitle("SOS Flashlight")
        .onDisappear { controller.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { controller.stop() } }
    }
}

private struct SatelliteGuideView: View {
    private let emergencySteps = [
        "Try calling the local emergency number first.",
        "If the call will not connect, tap Emergency Text via Satellite. You can also open Messages, text the local emergency number, then tap Emergency Services.",
        "Tap Report Emergency.",
        "Answer the emergency questions.",
        "Choose whether to notify your emergency contacts.",
        "Go outside with a clear view of the sky and horizon, then follow the onscreen pointing guide.",
        "Stay connected and follow the onscreen instructions while messages are sent."
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AuroraDesign.Space.lg) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Before leaving coverage").font(.headline)
                    Text("Set up Medical ID and emergency contacts in the Health app.")
                }.toolCard()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Emergency SOS via satellite").font(.headline)
                    ForEach(Array(emergencySteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .frame(width: 24, height: 24)
                                .background(AuroraDesign.signal, in: Circle())
                                .foregroundStyle(.white)
                            Text(step)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.font(.subheadline).toolCard()
                Text("Off-grid shortcut: Control Center → Cellular → Satellite → Emergency SOS, or Settings → Satellite.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .toolCard()
            }.padding().frame(maxWidth: AuroraDesign.readableWidth).frame(maxWidth: .infinity)
        }.navigationTitle("Satellite")
    }
}

private struct CompassToolView: View {
    @ObservedObject var location: SurvivalToolsLocationModel

    var body: some View {
        VStack(spacing: AuroraDesign.Space.lg) {
            Spacer()
            ZStack {
                Circle().fill(.thinMaterial).frame(width: 260, height: 260)
                Image(systemName: "location.north.fill").font(.system(size: 118)).foregroundStyle(AuroraDesign.river)
                    .rotationEffect(.degrees(-(location.latestFix?.heading ?? 0)))
                    .animation(.smooth, value: location.latestFix?.heading)
            }
            Text(headingText).font(.largeTitle.monospacedDigit().bold())
            if let fix = location.latestFix {
                Text(String(format: "%.6f, %.6f", fix.coordinate.latitude, fix.coordinate.longitude))
                    .font(.headline.monospaced())
                Text("Accuracy ±\(Int(max(0, fix.horizontalAccuracy))) m").font(.caption).foregroundStyle(.secondary)
            } else if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                Label("Location access is off. Enable it in Settings to use Compass.", systemImage: "location.slash.fill")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Finding your location…")
            }
            Text("Keep iPhone away from magnets and metal. Move it in a figure eight if heading accuracy appears poor.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding().navigationTitle("Compass")
        .onAppear { location.start() }.onDisappear { location.stop() }
    }

    private var headingText: String {
        guard let heading = location.latestFix?.heading else { return "—°" }
        return "\(Int(heading.rounded()))° \(cardinal(heading))"
    }

    private func cardinal(_ heading: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return points[Int((heading + 22.5) / 45) % 8]
    }
}

private struct TripChecklistView: View {
    @ObservedObject var store: TripChecklistStore
    @State private var editsItem: TripChecklistItem?
    @State private var addsItem = false

    var body: some View {
        List {
            Section {
                ProgressView(value: Double(store.completedCount), total: Double(max(1, store.items.count))) {
                    Text("\(store.completedCount) of \(store.items.count) prepared")
                }
            }
            ForEach(store.categories, id: \.self) { category in
                Section(category) {
                    ForEach(store.items.filter { $0.category == category }) { item in
                        Button { store.toggle(item) } label: {
                            Label {
                                Text(item.title).strikethrough(item.isComplete).foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isComplete ? .green : .secondary)
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { store.delete(item) }
                            Button("Edit") { editsItem = item }.tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Trip Checklist")
        .toolbar { Button { addsItem = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add checklist item") }
        .sheet(isPresented: $addsItem) {
            ChecklistItemEditor(title: "", category: "Custom") { store.add(title: $0, category: $1) }
        }
        .sheet(item: $editsItem) { item in
            ChecklistItemEditor(title: item.title, category: item.category) { store.update(item, title: $0, category: $1) }
        }
    }
}

private struct ChecklistItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var title: String
    @State var category: String
    let save: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form { TextField("Item", text: $title); TextField("Category", text: $category) }
                .navigationTitle("Checklist Item")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save(title, category); dismiss() }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}

private struct ToolsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @ObservedObject var checklistStore: TripChecklistStore
    @State private var confirmsReset = false

    var body: some View {
        NavigationStack {
            List {
                Section("About") {
                    LabeledContent("Version", value: version)
                    LabeledContent("Selected model", value: model.modelSelection.displayName)
                    LabeledContent("Loaded model", value: model.loadedTier?.displayName ?? "Not loaded")
                    LabeledContent("Installed AI", value: model.installedTierSummary)
                }
                Section("Legal") {
                    NavigationLink("AI Usage Disclosure") { LegalDocumentView(document: .ai) }
                    NavigationLink("Terms of Use") { LegalDocumentView(document: .terms) }
                    NavigationLink("Safety & Liability") { LegalDocumentView(document: .safety) }
                    NavigationLink("Privacy") { LegalDocumentView(document: .privacy) }
                }
                Section {
                    Button("Reset to Defaults", role: .destructive) { confirmsReset = true }
                        .accessibilityIdentifier("tools.reset")
                } footer: {
                    Text("Resets model and checklist preferences. Emergency information, chats, trails, maps, and downloads are preserved.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
            .confirmationDialog("Reset preferences to defaults?", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("Reset Preferences", role: .destructive) {
                    checklistStore.reset(); model.modelSelection = .lite
                    Task { await model.unloadModel() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var version: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(marketing) (\(build))"
    }
}

private struct LegalDocument {
    let title: String
    let introduction: String
    let sections: [(String, String)]

    static let ai = LegalDocument(title: "AI Usage Disclosure",
        introduction: "Beta notice: this disclosure is drafted for Aurora’s beta release and should receive professional legal review before production distribution.", sections: [
            ("Offline AI", "Aurora uses locally installed language, vision, embedding, and retrieval models. Outputs are probabilistic and may be incomplete, outdated, misunderstood, or wrong even when confident or accompanied by reviewed sources."),
            ("Not professional advice", "Aurora is not a medical professional, emergency dispatcher, rescue service, navigator, attorney, mechanic, or substitute for trained judgment. Do not delay contacting qualified emergency services because of an Aurora response."),
            ("User verification", "Check critical instructions against conditions, official guidance, product labels, and qualified professionals. Stop any action that appears unsafe or exceeds your skills, equipment, or physical condition."),
            ("Photos", "Expert may analyze only a photo you deliberately capture or select after contextual permission. Image interpretation can miss hazards, injuries, text, scale, depth, and environmental context."),
        ])
    static let terms = LegalDocument(title: "Beta Terms of Use",
        introduction: "By using this beta, you agree to use Aurora lawfully, responsibly, and subject to these limitations. If you do not agree, do not use the beta.", sections: [
            ("Permitted use", "Aurora is a preparation and informational aid. You are responsible for your decisions, route, equipment, communications, compliance with local law, and the safety of people affected by your actions."),
            ("Emergency services", "Aurora does not place emergency calls, dispatch responders, guarantee communication, or create a rescue relationship. Call the applicable local emergency number whenever circumstances require it."),
            ("Third-party services", "Maps, Apple satellite features, carriers, emergency systems, external links, model licenses, and other third-party services have separate availability, terms, fees, and privacy practices."),
            ("Changes", "Beta features, models, datasets, compatibility, and these terms may change. Material legal text should be versioned and reviewed before production."),
        ])
    static let safety = LegalDocument(title: "Safety & Liability",
        introduction: "Outdoor and emergency activities involve inherent risks, including serious injury, illness, property damage, getting lost, and death.", sections: [
            ("No warranty", "To the maximum extent permitted by law, the beta is provided as-is and as-available without warranties of accuracy, fitness for a particular purpose, uninterrupted operation, availability, or successful rescue."),
            ("Medical and survival limits", "Coordinates can be inaccurate; compasses can be affected by interference; offline maps can be old; torch signals may not be seen; satellite features vary; and AI guidance may hallucinate. Maintain independent navigation, signaling, first-aid, shelter, food, water, and communication plans."),
            ("Limitation of liability", "To the maximum extent permitted by applicable law, Aurora’s developers and distributors are not liable for indirect, incidental, special, consequential, or exemplary loss arising from reliance on the beta. Rights that cannot legally be excluded remain unaffected."),
            ("User responsibility", "You decide whether conditions permit an action and accept responsibility for using information within your training and capabilities. Never perform a hazardous procedure merely because the app describes it."),
        ])
    static let privacy = LegalDocument(title: "Privacy",
        introduction: "Aurora is designed for offline use and data minimization.", sections: [
            ("Local information", "Emergency profile, checklist, conversations, trails, downloaded packages, and selected attachments stay on the device unless you deliberately share or remove them. Emergency profile storage uses iOS file protection."),
            ("Permissions", "Location is requested for coordinates, compass, maps, and explicitly started trails. Camera or Photo Library access is requested only when you choose an Expert attachment workflow. Denying a permission limits only the related feature."),
            ("Sharing and links", "Copy, Share, phone, map, and external-link actions leave Aurora at your direction and may be handled by another service under its terms. Do not share medical or location information with people you do not trust."),
            ("Beta review", "This beta text describes the current local implementation and is not a substitute for a finalized jurisdiction-specific privacy policy or legal review."),
        ])
}

private struct LegalDocumentView: View {
    let document: LegalDocument
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AuroraDesign.Space.lg) {
                Text(document.introduction).font(.callout.bold()).foregroundStyle(.secondary)
                ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.0).font(.headline)
                        Text(section.1).foregroundStyle(.secondary)
                    }
                }
                Text("Beta legal text · August 22, 2026").font(.caption).foregroundStyle(.tertiary)
            }.padding().frame(maxWidth: AuroraDesign.readableWidth, alignment: .leading).frame(maxWidth: .infinity)
        }.navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
    }
}

private extension View {
    func toolCard() -> some View {
        padding(AuroraDesign.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }
}
