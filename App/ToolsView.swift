import SwiftUI

struct ToolsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsDownloadAccess = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                hero
                selection
                tierCard(.lite)
                tierCard(.expert)
                downloadAccess
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Tools")
        .accessibilityIdentifier("tools.home")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: model.canUseAsk ? "cpu.fill" : "arrow.down.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                Spacer()
                Text(model.canUseAsk ? "ASK READY" : "MODEL REQUIRED")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            Text("Offline intelligence")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(model.canUseAsk
                 ? "\(model.activeTier?.displayName ?? "Model") is ready. Every answer stays on this device."
                 : "Install Lite to enable Ask. Expert unlocks after vision validation on capable hardware.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.92), Color.teal.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tools.modelHero")
    }

    private var selection: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Model selection")
                    .font(.headline)
                Text(model.modelRoutingDecision.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Menu {
                Button("Auto") { model.modelSelection = .automatic }
                Button("Lite") { model.modelSelection = .lite }
                    .disabled(!model.runtimeTiers.contains(.lite))
                Button("Expert") { model.modelSelection = .expert }
                    .disabled(true)
            } label: {
                Label(model.modelSelection.displayName, systemImage: "slider.horizontal.3")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("tools.modelSelection")
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func tierCard(_ tier: ModelTier) -> some View {
        let entry = model.modelCatalogEntries.first {
            $0.metadata["model_tier"] == tier.rawValue
        }
        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: tier == .lite ? "text.bubble.fill" : "eye.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tier == .lite ? .blue : .purple)
                    .frame(width: 48, height: 48)
                    .background(
                        (tier == .lite ? Color.blue : Color.purple).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tier.displayName)
                        .font(.title2.bold())
                    Text(tier == .lite ? "FAST · TEXT" : "LARGER · TEXT + VISION")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                statusBadge(for: tier, entry: entry)
            }

            Text(tier == .lite
                 ? "Gemma 3 1B for iPhone 13-class devices. Fully offline conversation with the same reviewed Manual context."
                 : "A larger 2B-class vision tier targeted at iPhone 17 Pro Max and iPad Pro with M2 or newer.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if tier == .expert {
                Label("Signed model and vision projector validation pending", systemImage: "lock.shield.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)
                Button("Validation pending") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                    .frame(maxWidth: .infinity)
            } else if let entry {
                modelAction(for: entry)
            } else {
                Button {
                    showsDownloadAccess = true
                } label: {
                    Label("Connect download catalog", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(tier == .lite ? Color.blue.opacity(0.22) : Color.purple.opacity(0.22))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tools.tier.\(tier.rawValue)")
    }

    private func statusBadge(
        for tier: ModelTier,
        entry: PackageCatalogEntry?
    ) -> some View {
        let label: String
        let color: Color
        if tier == .expert {
            label = "PENDING"
            color = .purple
        } else if model.activeTier == tier {
            label = "ACTIVE"
            color = .green
        } else if model.runtimeTiers.contains(tier) {
            label = "READY"
            color = .green
        } else if entry != nil {
            label = "AVAILABLE"
            color = .blue
        } else {
            label = "NOT INSTALLED"
            color = .secondary
        }
        return Text(label)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Status: \(label)")
    }

    @ViewBuilder
    private func modelAction(for entry: PackageCatalogEntry) -> some View {
        switch model.packageState(for: entry) {
        case .available:
            Button { model.startDownload(entry) } label: {
                Label("Download Lite", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.incidentModeEnabled)
        case let .downloading(fraction):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: fraction) {
                    Text("Downloading \(fraction.formatted(.percent.precision(.fractionLength(0))))")
                }
                Button("Pause") { model.cancelDownload(entry) }
                    .buttonStyle(.bordered)
            }
        case .installed:
            Button {
                model.modelSelection = .lite
            } label: {
                Label("Use Lite", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Try download again") { model.startDownload(entry) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.incidentModeEnabled)
            }
        }
    }

    private var downloadAccess: some View {
        DisclosureGroup("Download access", isExpanded: $showsDownloadAccess) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(
                    model.incidentModeEnabled ? "Incident mode" : "Preparation mode",
                    isOn: Binding(
                        get: { !model.incidentModeEnabled },
                        set: { model.incidentModeEnabled = !$0 }
                    )
                )
                .accessibilityIdentifier("download.mode")

                TextField("https://host/catalog.json", text: $model.catalogURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityLabel("Signed catalog URL")

                Button {
                    Task { await model.refreshCatalog() }
                } label: {
                    HStack {
                        Label("Verify signed catalog", systemImage: "signature")
                        Spacer()
                        if model.isLoadingCatalog { ProgressView() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.incidentModeEnabled || model.isLoadingCatalog)
                .accessibilityIdentifier("catalog.verify")

                Text(model.catalogStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("catalog.status")

                Label("Packages must pass signature, hash, size, entitlement, and device checks before activation.", systemImage: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
        }
        .font(.headline)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}
