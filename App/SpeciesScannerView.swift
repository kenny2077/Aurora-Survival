import AuroraSpeciesKit
import PhotosUI
import SwiftUI
import UIKit

struct SpeciesScannerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var photoItem: PhotosPickerItem?
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @State private var imageData: Data?
    @State private var previewImage: UIImage?
    @State private var results: [SpeciesResult] = []
    @State private var isClassifying = false
    @State private var errorMessage: String?
    @State private var sessionGeneration: UInt = 0

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if model.speciesPackDescriptor == nil {
                    setupCard(
                        availableHeight: max(
                            0,
                            geometry.size.height - (AuroraDesign.Space.md * 2)
                        )
                    )
                        .padding(AuroraDesign.Space.md)
                        .frame(maxWidth: AuroraDesign.readableWidth)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: AuroraDesign.Space.lg) {
                        scanner
                        Spacer(minLength: AuroraDesign.Space.lg)
                        VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
                            photoActions
                            coverageFooter
                        }
                    }
                    .padding(AuroraDesign.Space.md)
                    .frame(
                        maxWidth: AuroraDesign.readableWidth,
                        minHeight: geometry.size.height,
                        alignment: .top
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Species Detector")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.speciesPackDescriptor.map { "\($0.packageID)@\($0.version):\($0.encoderSHA256)" }) {
            guard model.speciesPackDescriptor != nil else { return }
            try? await model.prepareSpeciesClassifier()
        }
        .photosPicker(
            isPresented: $showsPhotoPicker,
            selection: $photoItem,
            matching: .images
        )
        .onChange(of: photoItem) { _, item in
            Task { await load(item) }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCaptureView(
                onCapture: { data in
                    showsCamera = false
                    select(data)
                },
                onCancel: { showsCamera = false },
                onFailure: { message in
                    showsCamera = false
                    errorMessage = message
                }
            )
            .ignoresSafeArea()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            clearSession()
            model.unloadSpeciesClassifier()
        }
        .onDisappear {
            clearSession()
            model.unloadSpeciesClassifier()
        }
        .alert("Species Detector", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Species recognition failed.")
        }
        .accessibilityIdentifier("species.home")
    }

    private var coverageFooter: some View {
        HStack(alignment: .top, spacing: AuroraDesign.Space.sm) {
            Image(systemName: "pawprint.fill")
                .font(.subheadline)
                .foregroundStyle(AuroraDesign.river)
            VStack(alignment: .leading, spacing: 3) {
                Text("504 supported North American animals")
                    .font(.subheadline.weight(.semibold))
                Text("Birds, mammals, reptiles, and amphibians. Identification runs offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AuroraDesign.Space.sm)
        .accessibilityIdentifier("species.coverage")
    }

    private func setupCard(availableHeight: CGFloat) -> some View {
        VStack(spacing: AuroraDesign.Space.lg) {
            Image("BioCLIPSetupHero")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: AuroraDesign.Radius.standard))
                .accessibilityLabel("Elk, eagle, bear, and turtle in a mountain landscape")

            Text("BioCLIP 2 Species Detector")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            setupControl
                .frame(maxWidth: 320)

            Spacer(minLength: AuroraDesign.Space.lg)

            VStack(spacing: AuroraDesign.Space.xs) {
                Text("Identify 504 North American birds, mammals, reptiles, and amphibians—fully offline.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("581 MB optional download")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 560, minHeight: availableHeight, alignment: .top)
        .accessibilityIdentifier("species.setup")
    }

    @ViewBuilder private var setupControl: some View {
        if model.speciesCatalogEntry == nil {
            Text("Species Detector is not available in the connected signed catalog.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            switch model.speciesPackageState {
            case .available:
                Button { model.startSpeciesSetup() } label: {
                    Text("Download")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("species.download")
            case let .downloading(fraction):
                let percentage = fraction.formatted(
                    .percent.precision(.fractionLength(0))
                )
                VStack(alignment: .leading, spacing: AuroraDesign.Space.xs) {
                    HStack {
                        Text("Downloading")
                        Spacer()
                        Text(percentage)
                            .monospacedDigit()
                            .accessibilityIdentifier("species.progressLabel")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(AuroraDesign.river)
                        .accessibilityLabel("Species Detector download progress")
                        .accessibilityValue(percentage)
                        .accessibilityIdentifier("species.progress")
                    Button("Pause") { model.cancelSpeciesSetup() }
                        .frame(maxWidth: .infinity)
                }
            case .verifying:
                ProgressView("Verifying download…")
            case .installing:
                ProgressView("Installing…")
            case let .paused(fraction):
                VStack(spacing: AuroraDesign.Space.xs) {
                    HStack {
                        Text("Paused")
                        Spacer()
                        Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(AuroraDesign.river)
                    Button { model.startSpeciesSetup() } label: {
                        Text("Resume")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            case .installed:
                ProgressView("Activating verified model…")
            case .updateAvailable:
                Button { model.startSpeciesSetup() } label: {
                    Text("Update")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            case let .failed(message, _):
                VStack(spacing: AuroraDesign.Space.xs) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button { model.startSpeciesSetup() } label: {
                        Text("Retry")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    private var scanner: some View {
        VStack(spacing: AuroraDesign.Space.md) {
            if model.speciesRuntimeState == .preparing {
                HStack(spacing: AuroraDesign.Space.sm) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preparing Species Detector")
                            .font(.subheadline.bold())
                        Text("You can choose a photo while the offline model loads.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .accessibilityIdentifier("species.preparing")
            }

            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("Selected wildlife photo")
            } else {
                ContentUnavailableView(
                    "Choose a clear wildlife photo",
                    systemImage: "camera.viewfinder"
                )
                .frame(minHeight: 280)
            }

            if let imageData {
                Button {
                    classify(imageData)
                } label: {
                    if isClassifying {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Identify Species").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isClassifying)
                .accessibilityIdentifier("species.identify")
            }

            if let runtimeError = model.speciesRuntimeError {
                VStack(alignment: .leading, spacing: AuroraDesign.Space.xs) {
                    Text(runtimeError)
                        .font(.caption)
                        .foregroundStyle(.red)
                    HStack {
                        if let imageData {
                            Button("Retry") { classify(imageData) }
                                .disabled(isClassifying)
                        }
                        Button("Remove Model", role: .destructive) {
                            clearSession()
                            model.removeSpeciesSetup()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("species.runtimeError")
            }

            if !results.isEmpty {
                resultList
            }
        }
    }

    private var photoActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AuroraDesign.Space.sm) { photoButtons }
            VStack(spacing: AuroraDesign.Space.sm) { photoButtons }
        }
        .font(.subheadline.weight(.semibold))
        .controlSize(.regular)
        .buttonStyle(.bordered)
        .disabled(isClassifying)
    }

    @ViewBuilder private var photoButtons: some View {
        Button { showsCamera = true } label: {
            Label("Take Photo", systemImage: "camera.fill")
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, minHeight: 27)
        }
        .accessibilityIdentifier("species.camera")

        Button { showsPhotoPicker = true } label: {
            Label("Choose Photo", systemImage: "photo.on.rectangle")
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, minHeight: 27)
        }
        .accessibilityIdentifier("species.library")
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
            Text("Likely matches").font(.title3.bold())
            Text("Match scores compare only the 504 supported species; they are not certainty estimates.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(results, id: \.rank) { result in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(result.rank). \(result.name)").font(.headline)
                        Spacer()
                        Text(result.matchScore, format: .percent.precision(.fractionLength(1)))
                            .font(.subheadline.monospacedDigit())
                    }
                    Text(result.scientificName).font(.subheadline).italic()
                    if let danger = result.danger {
                        Label(danger.capitalized + " danger", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                    if let note = result.dangerNote, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(AuroraDesign.Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("species.result.\(result.rank)")
            }
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let generation = sessionGeneration
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw SpeciesClassifierError.imageDecodeFailed
            }
            guard generation == sessionGeneration else { return }
            select(data)
        } catch {
            guard generation == sessionGeneration else { return }
            errorMessage = error.localizedDescription
        }
        photoItem = nil
    }

    private func select(_ data: Data) {
        guard let image = UIImage(data: data) else {
            errorMessage = SpeciesClassifierError.imageDecodeFailed.localizedDescription
            return
        }
        imageData = data
        previewImage = image.preparingThumbnail(of: CGSize(width: 900, height: 900)) ?? image
        results = []
        errorMessage = nil
    }

    private func classify(_ data: Data) {
        isClassifying = true
        let generation = sessionGeneration
        Task {
            defer {
                if generation == sessionGeneration { isClassifying = false }
            }
            do {
                let matches = try await model.classifySpecies(imageData: data)
                guard generation == sessionGeneration else { return }
                results = matches
                imageData = nil
            } catch {
                guard generation == sessionGeneration, !(error is CancellationError) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clearSession() {
        sessionGeneration &+= 1
        imageData = nil
        previewImage = nil
        results = []
        errorMessage = nil
    }
}
