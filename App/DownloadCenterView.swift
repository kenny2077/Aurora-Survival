import SwiftUI

struct DownloadCenterView: View {
    @EnvironmentObject private var model: AppModel
    let kindFilter: PackageKind?
    let showsCatalogConnection: Bool
    let onOpenMap: ((String, OfflineMapLayer) -> Void)?

    init(
        kindFilter: PackageKind? = nil,
        showsCatalogConnection: Bool = true,
        onOpenMap: ((String, OfflineMapLayer) -> Void)? = nil
    ) {
        self.kindFilter = kindFilter
        self.showsCatalogConnection = showsCatalogConnection
        self.onOpenMap = onOpenMap
    }

    private var visibleEntries: [PackageCatalogEntry] {
        model.catalogEntries.filter { entry in
            kindFilter.map { entry.kind == $0 } ?? true
        }
    }

    private var installedMapsWithoutCatalogEntries: [ResolvedOfflineMap] {
        model.offlineMaps.filter { map in
            !visibleEntries.contains { $0.packageID == map.id }
        }
    }

    var body: some View {
        List {
            if showsCatalogConnection {
                catalogSection
            }

            if kindFilter == .map,
               !installedMapsWithoutCatalogEntries.isEmpty {
                installedMapSection
            }

            if visibleEntries.isEmpty
                && installedMapsWithoutCatalogEntries.isEmpty {
                Section {
                    ContentUnavailableView(
                        kindFilter == .map ? "No map catalog loaded" : "No downloads loaded",
                        systemImage: kindFilter == .map ? "map" : "arrow.down.circle",
                        description: Text("Connect to a signed catalog to see available offline packages.")
                    )
                }
            } else {
                packageSection(
                    title: "Offline intelligence",
                    kind: .model
                )
                packageSection(
                    title: "Guide & manual",
                    kind: .knowledge
                )
                packageSection(
                    title: "Offline maps",
                    kind: .map
                )
            }

            if showsCatalogConnection {
                Section("Safety boundary") {
                    Label(
                        "Every download is signed, hash verified, and atomically activated. Partial or tampered files never become active.",
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.callout)
                }
            }
        }
        .navigationTitle(kindFilter == .map ? "Offline Maps" : "Downloads")
    }

    private var catalogSection: some View {
        Section("Signed catalog") {
            TextField(
                "https://host/catalog.json",
                text: $model.catalogURLString
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .accessibilityLabel("Signed catalog URL")

            Button {
                Task { await model.refreshCatalog() }
            } label: {
                HStack {
                    Label("Verify catalog", systemImage: "signature")
                    Spacer()
                    if model.isLoadingCatalog {
                        ProgressView()
                    }
                }
            }
            .disabled(model.isLoadingCatalog)
            .accessibilityIdentifier("catalog.verify")

            Text(model.catalogStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Catalog status: \(model.catalogStatus)")
                .accessibilityIdentifier("catalog.status")
        }
    }

    @ViewBuilder
    private func packageSection(title: String, kind: PackageKind) -> some View {
        let entries = visibleEntries.filter { $0.kind == kind }
        if !entries.isEmpty {
            Section(title) {
                ForEach(entries) { entry in
                    let installedMap = model.offlineMaps.first {
                        $0.id == entry.packageID
                    }
                    PackageDownloadCard(
                        entry: entry,
                        state: model.packageState(for: entry),
                        start: { model.startDownload(entry) },
                        cancel: { model.cancelDownload(entry) },
                        remove: { model.removePackage(entry) },
                        mapLayers: installedMap?.pack.availableLayers ?? [],
                        openMap: { layer in
                            onOpenMap?(installedMap?.id ?? entry.packageID, layer)
                        }
                    )
                }
            }
        }
    }

    private var installedMapSection: some View {
        Section("Installed") {
            ForEach(installedMapsWithoutCatalogEntries) { map in
                HStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .accessibilityHidden(true)
                    Text(map.pack.name)
                        .font(.headline)
                        .accessibilityIdentifier("downloads.map.name.\(map.id)")
                    Spacer(minLength: 8)
                    compactOpenMap(
                        id: map.id,
                        layers: map.pack.availableLayers
                    )
                }
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private func compactOpenMap(id: String, layers: [OfflineMapLayer]) -> some View {
        if let onlyLayer = layers.first, layers.count == 1 {
            Button("Open Map") {
                onOpenMap?(id, onlyLayer)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityIdentifier("downloads.map.open.\(id)")
        } else if !layers.isEmpty {
            Menu("Open Map") {
                ForEach(layers, id: \.self) { layer in
                    Button {
                        onOpenMap?(id, layer)
                    } label: {
                        Label(layer.displayName, systemImage: layerIcon(layer))
                    }
                    .accessibilityIdentifier(
                        "downloads.map.layer.\(layer.rawValue)"
                    )
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityIdentifier("downloads.map.open.\(id)")
        }
    }

    private func layerIcon(_ layer: OfflineMapLayer) -> String {
        switch layer {
        case .legacy: "map"
        case .terrain: "mountain.2"
        case .topographic: "lines.measurement.horizontal"
        case .trail: "figure.hiking"
        }
    }

}

struct PackageDownloadCard: View {
    let entry: PackageCatalogEntry
    let state: PackageDownloadState
    let start: () -> Void
    let cancel: () -> Void
    let remove: () -> Void
    let mapLayers: [OfflineMapLayer]
    let openMap: (OfflineMapLayer) -> Void
    @State private var confirmsRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color("SignalOrange"))
                    .frame(width: 34, height: 34)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.headline)
                        .accessibilityIdentifier(
                            entry.kind == .map && isInstalledMap
                                ? "downloads.map.name.\(entry.id)"
                                : "package.title.\(entry.id)"
                        )
                    Text(entry.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isInstalledMap {
                    compactMapOpenAction
                }
            }
            HStack(spacing: 8) {
                Label(byteCount, systemImage: "internaldrive")
                if let region = entry.metadata["region"] {
                    Label(region, systemImage: "mappin.and.ellipse")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            action
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("package.\(entry.id)")
        .confirmationDialog(
            "Remove \(entry.displayName)?",
            isPresented: $confirmsRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove Download", role: .destructive, action: remove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The signed local files will be deleted. You can download them again later.")
        }
    }

    @ViewBuilder
    private var action: some View {
        switch state {
        case .available:
            Button(action: start) {
                Label("Download", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case let .downloading(fraction):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: fraction) {
                    Text("Downloading \(fraction.formatted(.percent.precision(.fractionLength(0))))")
                }
                Button("Pause", role: .cancel, action: cancel)
                    .buttonStyle(.bordered)
            }
            .accessibilityValue(fraction.formatted(.percent))

        case let .installed(active):
            HStack {
                Label(
                    active ? "Installed & active" : "Installed",
                    systemImage: active ? "checkmark.seal.fill" : "checkmark.circle.fill"
                )
                .font(.subheadline.bold())
                .foregroundStyle(.green)
                Spacer()
                Button("Remove", role: .destructive) {
                    confirmsRemoval = true
                }
                .buttonStyle(.bordered)
            }

        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Resume", action: start)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var icon: String {
        switch entry.kind {
        case .model: "cpu"
        case .knowledge: "books.vertical"
        case .map: "map"
        }
    }

    private var isInstalledMap: Bool {
        guard entry.kind == .map, !mapLayers.isEmpty else { return false }
        if case .installed = state { return true }
        return false
    }

    @ViewBuilder private var compactMapOpenAction: some View {
        if let onlyLayer = mapLayers.first, mapLayers.count == 1 {
            Button("Open Map") {
                openMap(onlyLayer)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityIdentifier("downloads.map.open.\(entry.id)")
        } else if !mapLayers.isEmpty {
            Menu("Open Map") {
                ForEach(mapLayers, id: \.self) { layer in
                    Button {
                        openMap(layer)
                    } label: {
                        Label(layer.displayName, systemImage: layerIcon(layer))
                    }
                    .accessibilityIdentifier(
                        "downloads.map.layer.\(layer.rawValue)"
                    )
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityIdentifier("downloads.map.open.\(entry.id)")
        }
    }

    private var byteCount: String {
        ByteCountFormatter.string(
            fromByteCount: entry.totalByteCount,
            countStyle: .file
        )
    }

    private func layerIcon(_ layer: OfflineMapLayer) -> String {
        switch layer {
        case .legacy: "map"
        case .terrain: "mountain.2"
        case .topographic: "lines.measurement.horizontal"
        case .trail: "figure.hiking"
        }
    }
}
