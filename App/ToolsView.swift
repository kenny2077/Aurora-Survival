import CoreLocation
import SwiftUI

struct ToolsView: View {
    private enum ToolRoute: Hashable {
        case emergency
        case flashlight
        case satellite
        case compass
        case checklist
        case species
#if AURORA_MESH_BETA
        case mesh
#endif
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var emergencyStore = EmergencyProfileStore()
    @StateObject private var checklistStore = TripChecklistStore()
    @StateObject private var locationModel = SurvivalToolsLocationModel()
    @StateObject private var flashlight = SOSFlashlightController()
    @State private var showsSettings = false
    @State private var modelPendingRemoval: ModelTier?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AuroraDesign.Space.lg) {
                offlineModels
                Text("Field tools").font(.title2.bold())
                GlassEffectContainer(spacing: AuroraDesign.Space.sm) {
                    fieldToolsGrid
                }
            }
            .padding(AuroraDesign.Space.md)
            .frame(maxWidth: AuroraDesign.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Tools")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsSettings = true } label: { Image(systemName: "gearshape.fill") }
                    .accessibilityLabel("Tools settings")
                    .accessibilityIdentifier("tools.settings")
            }
        }
        .task { await model.ensureCatalogLoaded() }
        .sheet(isPresented: $showsSettings) {
            ToolsSettingsView(model: model, checklistStore: checklistStore)
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

    private var offlineModels: some View {
        VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
            Text("Offline Models").font(.title2.bold())
            GlassEffectContainer(spacing: AuroraDesign.Space.sm) {
                VStack(spacing: AuroraDesign.Space.sm) {
                    tierCard(.lite)
                    tierCard(.expert)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tools.offlineAI")
    }

    private func tierCard(_ tier: ModelTier) -> some View {
        let setupState = model.modelSetupState(for: tier)
        return VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
            HStack(spacing: AuroraDesign.Space.sm) {
                Image(systemName: tier == .lite ? "text.bubble.fill" : "eye.fill")
                    .font(.headline)
                    .foregroundStyle(tierAccent(tier))
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName).font(.headline)
                    Text(modelDescription(for: tier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: AuroraDesign.Space.sm)
                modelControl(tier, setupState: setupState)
            }

            modelProgress(tier, setupState: setupState)
        }
        .padding(AuroraDesign.Space.sm)
        .frame(maxWidth: .infinity, minHeight: 62)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .opacity(tier == .expert && !model.expertDeviceIsEligible ? 0.68 : 1)
        .contextMenu {
            if case .ready = setupState {
                Button("Remove Download", role: .destructive) {
                    modelPendingRemoval = tier
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tools.tier.\(tier.rawValue)")
    }

    @ViewBuilder private func modelControl(
        _ tier: ModelTier,
        setupState: ModelSetupState
    ) -> some View {
        if tier == .expert && !model.expertDeviceIsEligible {
            EmptyView()
        } else if case .loading(tier) = model.modelRuntimeState {
            ProgressView()
                .frame(width: 34, height: 34)
                .accessibilityLabel("Loading \(tier.displayName)")
                .accessibilityIdentifier("tools.model.loading.\(tier.rawValue)")
        } else if model.loadedTier == tier {
            Button {
                Task { await model.unloadModel() }
            } label: {
                Image(systemName: "eject.fill")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .accessibilityLabel("Unload \(tier.displayName)")
            .accessibilityIdentifier("tools.model.unload.\(tier.rawValue)")
        } else if model.runtimeTiers.contains(tier) {
            Button {
                Task { await model.loadModel(tier) }
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .disabled(model.isModelLoading)
            .accessibilityLabel("Load \(tier.displayName)")
            .accessibilityIdentifier("tools.model.load.\(tier.rawValue)")
        } else {
            switch setupState {
            case .ready:
                EmptyView()
            case .downloading:
                Button { model.cancelModelSetup(tier) } label: {
                    Image(systemName: "pause.fill")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Pause \(tier.displayName) download")
                .accessibilityIdentifier("tools.model.pause.\(tier.rawValue)")
            case let .paused(fraction):
                modelIconButton(
                    "play.fill",
                    label: "Resume \(tier.displayName) download at "
                        + fraction.formatted(.percent.precision(.fractionLength(0))),
                    identifier: "tools.model.resume.\(tier.rawValue)"
                ) {
                    model.startModelSetup(tier)
                }
            case .available:
                modelIconButton(
                    "arrow.down",
                    label: downloadLabel(tier),
                    identifier: "tools.model.download.\(tier.rawValue)"
                ) {
                    model.startModelSetup(tier)
                }
            case .updateAvailable:
                modelIconButton(
                    "arrow.down.circle",
                    label: "Update \(tier.displayName)",
                    identifier: "tools.model.update.\(tier.rawValue)"
                ) {
                    model.startModelSetup(tier)
                }
            case let .failed(message):
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    modelIconButton(
                        "arrow.clockwise",
                        label: "Retry \(tier.displayName)",
                        identifier: "tools.model.retry.\(tier.rawValue)",
                        hint: message
                    ) {
                        model.startModelSetup(tier)
                    }
                }
            case .unavailable:
                EmptyView()
            }
        }
    }

    @ViewBuilder private func modelProgress(
        _ tier: ModelTier,
        setupState: ModelSetupState
    ) -> some View {
        switch setupState {
        case let .downloading(fraction):
            progressRow(tier, fraction: fraction, paused: false)
        case let .paused(fraction):
            progressRow(tier, fraction: fraction, paused: true)
        default:
            EmptyView()
        }
    }

    private func progressRow(
        _ tier: ModelTier,
        fraction: Double,
        paused: Bool
    ) -> some View {
        let percentage = fraction.formatted(
            .percent.precision(.fractionLength(0))
        )
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(paused ? "Paused" : "Downloading")
                Spacer()
                Text(percentage)
                    .monospacedDigit()
                    .accessibilityIdentifier(
                        "tools.model.progressLabel.\(tier.rawValue)"
                    )
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(tierAccent(tier))
                .accessibilityLabel("\(tier.displayName) download progress")
                .accessibilityValue(percentage)
                .accessibilityIdentifier(
                    "tools.model.progress.\(tier.rawValue)"
                )
        }
    }

    private func modelDescription(for tier: ModelTier) -> String {
        switch tier {
        case .lite:
            "Fast offline text"
        case .expert where !model.expertDeviceIsEligible:
            "Requires a newer device"
        case .expert:
            "Offline text and photos"
        }
    }

    private func tierAccent(_ tier: ModelTier) -> Color {
        AuroraDesign.ordinaryAccent(
            light: tier == .lite ? AuroraDesign.river : .indigo,
            colorScheme: colorScheme
        )
    }

    private func modelIconButton(
        _ symbol: String,
        label: String,
        identifier: String,
        hint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
        .accessibilityIdentifier(identifier)
    }

    private func downloadLabel(_ tier: ModelTier) -> String {
        let bytes = model.modelSetupByteCount(for: tier)
        let base = "Download \(tier.displayName) + Knowledge"
        return bytes > 0 ? base + " · " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : base
    }

    @ViewBuilder private var fieldToolsGrid: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AuroraDesign.Space.sm) {
                fieldToolCards
            }
        } else if horizontalSizeClass == .regular {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible()),
                    count: 3
                ),
                spacing: AuroraDesign.Space.sm
            ) {
                fieldToolCards
            }
        } else {
            Grid(
                horizontalSpacing: AuroraDesign.Space.sm,
                verticalSpacing: AuroraDesign.Space.sm
            ) {
                GridRow {
                    emergencyTool.gridCellColumns(2)
                    flashlightTool.gridCellColumns(2)
                }
                GridRow {
                    satelliteTool.gridCellColumns(2)
                    compassTool.gridCellColumns(2)
                }
                GridRow {
                    checklistTool.gridCellColumns(2)
                    speciesTool.gridCellColumns(2)
                }
#if AURORA_MESH_BETA
                GridRow {
                    meshTool.gridCellColumns(2)
                    Color.clear
                        .accessibilityHidden(true)
                        .gridCellColumns(2)
                }
#endif
            }
        }
    }

    @ViewBuilder private var fieldToolCards: some View {
        emergencyTool
        flashlightTool
        satelliteTool
        compassTool
        checklistTool
        speciesTool
#if AURORA_MESH_BETA
        meshTool
#endif
    }

    private var emergencyTool: some View {
        toolLink(
            "Emergency Center",
            "SOS & emergency info",
            "sos.circle.fill",
            AuroraDesign.signal,
            route: .emergency,
            identifier: "tools.emergency"
        )
    }

    private var flashlightTool: some View {
        toolLink(
            "SOS Flashlight",
            flashlight.isRunning ? "SIGNALING" : "Morse torch signal",
            "flashlight.on.fill",
            .orange,
            route: .flashlight
        )
    }

    private var satelliteTool: some View {
        toolLink(
            "Satellite",
            "Compatibility & guide",
            "antenna.radiowaves.left.and.right",
            AuroraDesign.ordinaryAccent(
                light: .indigo,
                colorScheme: colorScheme
            ),
            route: .satellite
        )
    }

    private var compassTool: some View {
        toolLink(
            "Compass",
            "Heading & coordinates",
            "safari.fill",
            AuroraDesign.river,
            route: .compass
        )
    }

    private var checklistTool: some View {
        toolLink(
            "Checklist",
            "\(checklistStore.completedCount) of \(checklistStore.items.count) ready",
            "checklist.checked",
            AuroraDesign.ordinaryAccent(
                light: .green,
                colorScheme: colorScheme
            ),
            route: .checklist
        )
    }

    private var speciesTool: some View {
        toolLink(
            "Species ID",
            model.speciesPackDescriptor == nil
                ? "Optional offline model"
                : "504 animals · Offline",
            "pawprint.fill",
            AuroraDesign.ordinaryAccent(
                light: .green,
                colorScheme: colorScheme
            ),
            route: .species,
            identifier: "tools.speciesID"
        )
    }

#if AURORA_MESH_BETA
    private var meshTool: some View {
        toolLink(
            "Mesh Chat",
            "Encrypted nearby groups · Beta",
            "point.3.connected.trianglepath.dotted",
            AuroraDesign.ordinaryAccent(light: .cyan, colorScheme: colorScheme),
            route: .mesh,
            identifier: "tools.meshChat"
        )
    }
#endif

    private func toolLink(
        _ title: String,
        _ detail: String,
        _ symbol: String,
        _ tint: Color,
        route: ToolRoute,
        identifier: String? = nil
    ) -> some View {
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
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 22))
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? "tools.tool.\(title)")
    }

    @ViewBuilder private func toolDestination(for route: ToolRoute) -> some View {
        switch route {
        case .emergency:
            EmergencyCenterView(store: emergencyStore, location: locationModel)
        case .flashlight:
            SOSFlashlightView(controller: flashlight)
        case .satellite:
            SatelliteGuideView()
        case .compass:
            CompassToolView(location: locationModel)
        case .checklist:
            TripChecklistView(store: checklistStore)
        case .species:
            SpeciesScannerView()
#if AURORA_MESH_BETA
        case .mesh:
            MeshChatView()
#endif
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
    @Environment(\.colorScheme) private var colorScheme
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
                            Button("Edit") { editsItem = item }
                                .tint(
                                    AuroraDesign.ordinaryAccent(
                                        light: .blue,
                                        colorScheme: colorScheme
                                    )
                                )
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
                Section("Appearance") {
                    Picker("Appearance", selection: $model.appearancePreference) {
                        ForEach(AppearancePreference.allCases) { preference in
                            Text(preference.displayName).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("tools.appearance")
                    .accessibilityValue(model.appearancePreference.displayName)
                }
                Section("About") {
                    LabeledContent("Version", value: version)
                    LabeledContent("Selected model", value: model.modelSelection.displayName)
                }
                Section("Downloads") {
                    Toggle(
                        "Allow Cellular Model Downloads",
                        isOn: $model.allowsCellularModelDownloads
                    )
                    Text("Model downloads use Wi-Fi by default. Enable cellular only after reviewing the model size with your carrier plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Legal") {
                    NavigationLink("Legal & Privacy") { LegalPrivacyHubView() }
                }
                Section {
                    Button("Reset to Defaults", role: .destructive) { confirmsReset = true }
                        .accessibilityIdentifier("tools.reset")
                } footer: {
                    Text("Resets model and checklist preferences. Emergency information, chats, trails, maps, and downloads are preserved.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset preferences to defaults?", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("Reset Preferences", role: .destructive) {
                    checklistStore.reset(); model.modelSelection = .lite
                    model.appearancePreference = .system
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

struct LegalPrivacyHubView: View {
    var body: some View {
        List {
            Section {
                NavigationLink("Aurora Terms & AI Use") {
                    CombinedAuroraAgreementView()
                }
                .accessibilityIdentifier("legal.agreement")

                NavigationLink("Privacy Notice") {
                    LegalDocumentView(document: .privacy)
                }
                .accessibilityIdentifier("legal.privacy")

                NavigationLink("Model Licenses & Notices") {
                    ModelLicensesAndNoticesView()
                }
                .accessibilityIdentifier("legal.models")
            } footer: {
                Text("All documents are stored with Aurora and remain available offline.")
            }
        }
        .navigationTitle("Legal & Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CombinedAuroraAgreementView: View {
    private let documents: [LegalDocument] = [.terms, .ai, .safety]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AuroraDesign.Space.xl) {
                ForEach(Array(documents.enumerated()), id: \.offset) { index, document in
                    VStack(alignment: .leading, spacing: AuroraDesign.Space.md) {
                        Text(document.title)
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text(document.introduction)
                            .font(.callout.bold())
                            .foregroundStyle(.secondary)
                        ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                            VStack(alignment: .leading, spacing: AuroraDesign.Space.xs) {
                                Text(section.0).font(.headline)
                                Text(section.1).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if index < documents.count - 1 { Divider() }
                }

                Text("Legal notices · September 7, 2026")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(AuroraDesign.Space.lg)
            .frame(maxWidth: AuroraDesign.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Aurora Terms & AI Use")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ModelLicensesAndNoticesView: View {
    var body: some View {
        List {
            Section("BioCLIP-2") {
                NavigationLink("MIT License") {
                    BundledLegalTextView(
                        title: "BioCLIP-2 MIT License",
                        resource: "LICENSE_MIT_BIOCLIP2",
                        fileExtension: "txt"
                    )
                }
                NavigationLink("Attribution") {
                    BundledLegalTextView(title: "BioCLIP-2 Attribution", resource: "BIOCLIP2_NOTICE")
                }
            }
            Section("Gemma") {
                NavigationLink("Gemma Terms of Use") {
                    BundledLegalTextView(
                        title: "Gemma Terms of Use",
                        resource: "GEMMA_TERMS_2026-04-01"
                    )
                }
                NavigationLink("Gemma Prohibited Use Policy") {
                    LegalDocumentView(document: .gemmaRestrictions)
                }
                NavigationLink("Gemma Modification Notice") {
                    BundledLegalTextView(
                        title: "Gemma Modification Notice",
                        resource: "GEMMA_MODIFICATIONS_NOTICE"
                    )
                }
            }

            Section("Qwen") {
                NavigationLink("Apache License 2.0") {
                    BundledLegalTextView(
                        title: "Apache License 2.0",
                        resource: "LICENSE_APACHE_2.0",
                        fileExtension: "txt"
                    )
                }
                NavigationLink("Redistribution Notice") {
                    BundledLegalTextView(
                        title: "Qwen Redistribution Notice",
                        resource: "QWEN_NOTICE"
                    )
                }
            }

            Section("BGE") {
                NavigationLink("MIT License") {
                    BundledLegalTextView(
                        title: "BGE MIT License",
                        resource: "LICENSE_MIT_BGE",
                        fileExtension: "txt"
                    )
                }
                NavigationLink("Conversion Notice") {
                    BundledLegalTextView(
                        title: "BGE Conversion Notice",
                        resource: "BGE_CONVERSION_NOTICE"
                    )
                }
            }
        }
        .navigationTitle("Model Licenses & Notices")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LegalDocument {
    let title: String
    let introduction: String
    let sections: [(String, String)]

    static let ai = LegalDocument(title: "AI Usage Disclosure",
        introduction: "Aurora uses on-device AI to provide information and likely image matches. AI output is not a guarantee of accuracy or safety.", sections: [
            ("Offline AI", "Aurora uses locally installed language, vision, embedding, and retrieval models. Outputs are probabilistic and may be incomplete, outdated, misunderstood, or wrong even when confident or accompanied by reviewed sources."),
            ("Not professional advice", "Aurora is not a medical professional, emergency dispatcher, rescue service, navigator, attorney, mechanic, or substitute for trained judgment. Do not delay contacting qualified emergency services because of an Aurora response."),
            ("User verification", "Check critical instructions against conditions, official guidance, product labels, and qualified professionals. Stop any action that appears unsafe or exceeds your skills, equipment, or physical condition."),
            ("Photos and wildlife", "Expert and Species ID analyze photos you choose. Images can omit hazards, injuries, scale, and context. Species ID covers 504 North American animals, not all wildlife; match scores are not calibrated probabilities. Do not approach, handle, or consume wildlife based only on photo identification."),
        ])
    static let terms = LegalDocument(title: "Terms of Use",
        introduction: "Aurora Survival is an educational preparation and reference tool. By choosing Agree & Continue, you accept these terms and acknowledge the AI and safety limitations. If you do not agree, do not continue.", sections: [
            ("Permitted use", "Aurora is a preparation and informational aid. You are responsible for your decisions, route, equipment, communications, compliance with local law, and the safety of people affected by your actions."),
            ("Emergency services", "Aurora does not place emergency calls, dispatch responders, guarantee communication, or create a rescue relationship. Call the applicable local emergency number whenever circumstances require it."),
            ("Gemma use restrictions", "Aurora Lite includes Google Gemma. You agree that your use of Gemma is governed by the Gemma Terms of Use and must not violate the incorporated Gemma Prohibited Use Policy, including prohibited dangerous, illegal, malicious, rights-infringing, deceptive, or privacy-invasive activity."),
            ("Third-party services", "Maps, Apple satellite features, carriers, emergency systems, external links, model licenses, and other third-party services have separate availability, terms, fees, and privacy practices."),
            ("Offline preparation", "Download and test any models or maps before travel. Downloads require connectivity, storage, and a compatible device; network or carrier charges may apply. Download servers may be unavailable or rate-limited. Installed features can still be affected by battery, heat, storage, permissions, and device failure."),
            ("Changes and rights", "App features, datasets, and compatibility may change with updates. Material changes to the acknowledgment require acceptance again. Nothing in these notices excludes rights or remedies that applicable law does not permit us to exclude."),
        ])
    static let safety = LegalDocument(title: "Safety & Liability",
        introduction: "Outdoor and emergency activities involve inherent risks, including serious injury, illness, property damage, getting lost, and death.", sections: [
            ("Availability and accuracy", "Aurora is provided as-is and as-available to the extent permitted by law. It does not guarantee accurate instructions, uninterrupted operation, communication, or successful rescue. Statutory rights remain unaffected."),
            ("Medical and survival limits", "Coordinates can be inaccurate; compasses can be affected by interference; offline maps can be old; torch signals may not be seen; satellite features vary; and AI guidance may hallucinate. Maintain independent navigation, signaling, first-aid, shelter, food, water, and communication plans."),
            ("Independent checks", "An AI answer, source citation, map marker, or species match is not a safety certification. Confirm critical decisions with official guidance, current conditions, and qualified help. Do not delay emergency care while using Aurora."),
            ("User responsibility", "You decide whether conditions permit an action and accept responsibility for using information within your training and capabilities. Never perform a hazardous procedure merely because the app describes it."),
        ])
    static let privacy = LegalDocument(title: "Privacy",
        introduction: "Aurora is designed for offline use and data minimization.", sections: [
            ("On-device processing", "Language and image inference run on your device. Aurora does not upload your prompts, selected photos, or location for AI inference and does not include advertising or tracking analytics. App settings, downloaded packages, and saved map or trail data are stored locally."),
            ("Photos", "Species ID keeps the selected photo and results only for the active scanner session; it does not save scanner captures to Photos or chat history. Expert attachments are a separate workflow and may remain visible in the active conversation. Photos saved through a photo-saving action are managed by your Photos library and its backup settings."),
            ("Permissions and location", "Camera and photo permissions support the actions you choose. Location supports maps, coordinates, compass, and explicitly started trails; a running trail may use location in the background until stopped. You can change permissions in iOS Settings. Denying access limits the related feature."),
            ("Downloads", "When you request models, maps, or catalogs, the hosting provider receives network information such as your IP address, requested file, and request timing. Cloudflare and other download providers process that information under their own privacy policies. These requests do not contain your scanner photos or AI prompts."),
            ("Sharing and links", "Copy, Share, phone, map, and external-link actions leave Aurora at your direction and may be handled by another service under its terms. Do not share medical or location information with people you do not trust."),
            ("Retention and device services", "Remove downloaded packages using Aurora’s controls. Uninstalling removes the app container, but copies you shared, Photos-library items, and device backups may remain under your control or the relevant provider’s settings. iOS may independently manage backups and diagnostics. Protect access to your device."),
        ])
    static let gemmaRestrictions = LegalDocument(
        title: "Gemma Prohibited Use Policy",
        introduction: "Gemma use is subject to Google's Gemma Terms of Use and the incorporated Prohibited Use Policy.",
        sections: [
            (
                "Enforceable restrictions",
                "You must not use Gemma for prohibited, dangerous, illegal, malicious, rights-infringing, deceptive, privacy-invasive, or otherwise unlawful activity. The complete current policy is available at ai.google.dev/gemma/prohibited_use_policy."
            ),
            (
                "Model distribution",
                "Aurora Lite includes an offline copy of the applicable Gemma Terms, the required Notice file, and a record of the GGUF conversion and quantization."
            ),
        ]
    )
}

struct LegalDocumentView: View {
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
                Text("Legal notices · September 7, 2026").font(.caption).foregroundStyle(.tertiary)
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
