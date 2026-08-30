import PhotosUI
import SwiftUI

struct ChatView: View {
    private static let bundledAuroraIcon: UIImage? = {
        guard let url = Bundle.main.url(
            forResource: "AppIcon60x60@2x",
            withExtension: "png"
        ) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }()

    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showsAttachmentSourceDialog = false
    @State private var showsAttachmentMenu = false
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @State private var previewPhoto: PhotoPreview?
    @FocusState private var composerIsFocused: Bool

    var body: some View {
        VStack(spacing: AuroraDesign.Space.xs) {
            modelStatus
            if model.canUseAsk {
                messages
            } else {
                noModelChapters
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                modelControl
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: photoItem) { _, item in
            Task {
                guard let item else { return }
                model.beginAttachmentLoading()
                do {
                    guard let data = try await item.loadTransferable(
                        type: Data.self
                    ) else {
                        model.failAttachmentLoading(
                            "The selected image contained no readable data."
                        )
                        photoItem = nil
                        return
                    }
                    await model.attachSelectedPhoto(data: data)
                } catch {
                    model.failAttachmentLoading(
                        "The selected image could not be loaded: \(error.localizedDescription)"
                    )
                }
                photoItem = nil
            }
        }
        .onAppear { model.refreshPhotoAuthorizationStatus() }
        .confirmationDialog(
            model.draftImageAttachment == nil ? "Add a picture" : "Replace picture",
            isPresented: $showsAttachmentSourceDialog,
            titleVisibility: .visible
        ) {
            Button("Take Photo") { takePhoto() }
            Button("Choose Existing Photo") { chooseExistingPhoto() }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showsPhotoPicker,
            selection: $photoItem,
            matching: .images
        )
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCaptureView(
                onCapture: { data in
                    showsCamera = false
                    Task { await model.attachCapturedPhoto(data: data) }
                },
                onCancel: {
                    showsCamera = false
                    model.clearAttachmentOperationState()
                },
                onFailure: { message in
                    showsCamera = false
                    model.failAttachmentLoading(message)
                }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $previewPhoto) { preview in
            PhotoPreviewView(preview: preview) {
                previewPhoto = nil
            }
        }
    }

    private var noModelChapters: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 40) {
                    VStack(spacing: AuroraDesign.Space.sm) {
                        auroraGuideIcon
                            .accessibilityLabel("Aurora")
                            .accessibilityIdentifier(
                                "chat.survivalGuideIcon"
                            )
                        Text("Survival Guide")
                            .font(.title.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    LazyVGrid(
                        columns: noModelChapterColumns,
                        spacing: AuroraDesign.Space.sm
                    ) {
                        ForEach(model.fieldGuideChapters) { chapter in
                            Button {
                                model.openManualChapter(chapter.id)
                            } label: {
                                HStack(spacing: AuroraDesign.Space.xs) {
                                    Image(systemName: chapter.symbol)
                                        .accessibilityHidden(true)
                                    Text(chapter.title)
                                }
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier(
                                "chat.manual-chapter.\(chapter.id)"
                            )
                        }
                    }
                }
                .frame(maxWidth: AuroraDesign.readableWidth)
                .frame(
                    minHeight: max(
                        0,
                        geometry.size.height
                            - AuroraDesign.Space.md
                            - AuroraDesign.Space.lg
                    ),
                    alignment: .bottom
                )
                .padding(.horizontal, AuroraDesign.Space.md)
                .padding(.top, AuroraDesign.Space.md)
                .padding(.bottom, AuroraDesign.Space.lg)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("chat.modelRequired")
    }

    @ViewBuilder
    private var auroraGuideIcon: some View {
        if let icon = Self.bundledAuroraIcon {
            Image(uiImage: icon)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: AuroraDesign.Radius.standard
                    )
                )
                .frame(width: 76, height: 76)
                .offset(y: -16)
        } else {
            Image(systemName: "mountain.2.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .background(
                    AuroraDesign.aurora(colorScheme: colorScheme),
                    in: RoundedRectangle(
                        cornerRadius: AuroraDesign.Radius.standard
                    )
                )
                .frame(width: 76, height: 76)
                .offset(y: -16)
        }
    }

    private var noModelChapterColumns: [GridItem] {
        let count: Int
        if dynamicTypeSize.isAccessibilitySize {
            count = 1
        } else if horizontalSizeClass == .regular {
            count = 3
        } else {
            count = 2
        }
        return Array(
            repeating: GridItem(
                .flexible(),
                spacing: AuroraDesign.Space.sm
            ),
            count: count
        )
    }

    private var messages: some View {
        GeometryReader { geometry in
            if model.messages.isEmpty {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text("How can I help?")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                    Color.clear
                        .frame(height: geometry.size.height * 0.12)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded { dismissComposer() }
                    )
                    .accessibilityIdentifier("chat.greeting")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: AuroraDesign.Space.lg) {
                            ForEach(model.messages) { message in
                                VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
                                    if model.isThinking,
                                       message.role == .assistant,
                                       message.id == model.messages.last?.id {
                                        thinkingIndicator
                                    }
                                    MessageBubble(message: message) { data in
                                        previewPhoto = PhotoPreview(
                                            data: data,
                                            accessibilityLabel: "Sent photo"
                                        )
                                    }
                                }
                                .id(message.id)
                            }
                        }
                        .frame(maxWidth: AuroraDesign.readableWidth)
                        .frame(
                            minHeight: geometry.size.height,
                            alignment: .top
                        )
                        .padding(.horizontal, AuroraDesign.Space.md)
                        .padding(.vertical, AuroraDesign.Space.lg)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(
                        TapGesture().onEnded { dismissComposer() }
                    )
                    .onChange(of: model.messages.count) {
                        guard let first = model.messages.first else { return }
                        if model.messages.count <= 2 {
                            proxy.scrollTo(first.id, anchor: .top)
                        } else if let last = model.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: AuroraDesign.Space.xs) {
            ProgressView()
            Text("Thinking offline…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .accessibilityIdentifier("chat.thinking")
    }

    private var composer: some View {
        VStack(spacing: AuroraDesign.Space.xs) {
            if model.canAttachPhoto,
               let attachment = model.draftImageAttachment {
                VStack(alignment: .leading, spacing: AuroraDesign.Space.xxs) {
                    attachmentPreviewTile(attachment)
                    if let message = attachmentFailureMessage(attachment) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("chat.attachment.error")
                    }
                }
                .padding(.horizontal, AuroraDesign.Space.xs)
            } else if model.canAttachPhoto,
                      case .loading = model.attachmentOperationState {
                ProgressView()
                    .frame(width: 64, height: 64)
                    .padding(.horizontal, AuroraDesign.Space.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Loading photo")
                    .accessibilityIdentifier("chat.attachment.loading")
            }

            if model.canAttachPhoto {
                attachmentOperationFeedback
            }

            GlassEffectContainer(spacing: AuroraDesign.Space.xs) {
                ZStack(alignment: .bottom) {
                    composerTextField
                        .padding(
                            .leading,
                            composerIsExpanded
                                ? AuroraDesign.Space.xs
                                : 56
                        )
                        .padding(.trailing, 44)
                        .padding(
                            .top,
                            composerIsExpanded ? AuroraDesign.Space.xs : 0
                        )
                        .padding(
                            .bottom,
                            composerIsExpanded ? 44 : 0
                        )
                        .frame(
                            maxWidth: .infinity,
                            minHeight: composerIsExpanded ? 104 : 44,
                            alignment: composerIsExpanded ? .topLeading : .center
                        )

                    HStack(spacing: AuroraDesign.Space.xs) {
                        photoAttachmentControl
                        Spacer()
                        sendButton
                    }
                }
                .padding(AuroraDesign.Space.xxs)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(
                        cornerRadius: composerIsExpanded ? 30 : 26
                    )
                )
            }
            .animation(.smooth(duration: 0.24), value: composerIsExpanded)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat.composerSurface")

            if model.canAttachPhoto,
               model.photoAuthorizationStatus == .denied
                || model.photoAuthorizationStatus == .restricted {
                HStack {
                    Text("Photo access is disabled. Enable access in Settings to attach an image.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Settings") { model.openPhotoSettings() }
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, AuroraDesign.Space.xs)
            }
        }
        .frame(maxWidth: AuroraDesign.readableWidth)
        .padding(.horizontal, AuroraDesign.Space.md)
        .padding(.top, AuroraDesign.Space.xxs)
        .padding(.bottom, AuroraDesign.Space.xs)
        .frame(maxWidth: .infinity)
    }

    private var composerTextField: some View {
        TextField(
            model.canUseAsk
                ? "Ask anything…"
                : "Select a model to start a chat",
            text: $draft,
            axis: .vertical
        )
            .lineLimit(1...5)
            .focused($composerIsFocused)
            .disabled(!model.canUseAsk)
            .accessibilityIdentifier("chat.composer")
    }

    private var sendButton: some View {
        Group {
            if canSend {
                sendButtonControl
                    .buttonStyle(.glassProminent)
                    .tint(Color.accentColor)
                    .foregroundStyle(Color(uiColor: .systemBackground))
            } else {
                sendButtonControl
                    .buttonStyle(.glass)
                    .disabled(true)
                    .overlay {
                        Image(systemName: "arrow.up")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.primary)
                            .accessibilityHidden(true)
                    }
            }
        }
    }

    private var sendButtonControl: some View {
        Button(action: sendDraft) {
            Image(systemName: "arrow.up")
                .font(.callout.weight(.bold))
                .frame(width: 28, height: 28)
        }
        .buttonBorderShape(.circle)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("Send")
        .accessibilityIdentifier("chat.send")
    }

    private func sendDraft() {
        let outgoing = draft
        draft = ""
        composerIsFocused = false
        Task { await model.send(outgoing) }
    }

    private var composerIsExpanded: Bool {
        composerIsFocused || !draft.isEmpty
    }

    @ViewBuilder
    private var photoAttachmentControl: some View {
        Button {
            showsAttachmentMenu = true
        } label: {
            Image(systemName: "plus")
                .font(.callout.weight(.semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("Attach photo")
        .accessibilityIdentifier("chat.attach")
        .popover(
            isPresented: $showsAttachmentMenu,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            attachmentMenu
                .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private var attachmentOperationFeedback: some View {
        switch model.attachmentOperationState {
        case .idle:
            EmptyView()
        case .loading:
            EmptyView()
        case let .failed(message, offersSettings):
            HStack(alignment: .firstTextBaseline, spacing: AuroraDesign.Space.xs) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if offersSettings {
                    Button("Settings") { model.openPhotoSettings() }
                        .font(.caption.weight(.semibold))
                }
                Button {
                    model.clearAttachmentOperationState()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Dismiss photo error")
            }
            .padding(.horizontal, AuroraDesign.Space.xs)
        }
    }

    private func chooseExistingPhoto() {
        Task {
            let status = await model.requestPhotoLibraryAccess()
            guard status.permitsSelection else {
                model.failAttachmentLoading(
                    status == .restricted
                        ? "Photo Library access is restricted on this device."
                        : "Photo Library access is denied. Enable it in Settings to choose an existing photo.",
                    offersSettings: status == .denied
                )
                return
            }
            showsPhotoPicker = true
        }
    }

    private func takePhoto() {
        Task {
            guard await model.prepareCameraCapture() else { return }
            showsCamera = true
        }
    }

    private func dismissComposer() {
        guard composerIsFocused else { return }
        withAnimation(.smooth(duration: 0.2)) {
            composerIsFocused = false
        }
    }

    private var canSend: Bool {
        guard model.canUseAsk, !model.isThinking else { return false }
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        guard let attachment = model.draftImageAttachment else { return false }
        return attachment.loadState == .ready && attachment.imageData != nil
    }

    @ViewBuilder
    private var modelControl: some View {
        if model.isModelLoading {
            ProgressView()
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Loading model")
                .accessibilityIdentifier("chat.modelSelection")
        } else {
            Menu {
                ForEach(ModelTier.allCases, id: \.self) { tier in
                    Button {
                        activateModel(tier)
                    } label: {
                        Label(
                            modelMenuTitle(for: tier),
                            systemImage: model.loadedTier == tier
                                ? "checkmark"
                                : model.runtimeTiers.contains(tier)
                                    ? "cpu"
                                    : "arrow.down.circle"
                        )
                    }
                    .disabled(tier == .expert && !model.expertDeviceIsEligible)
                    .accessibilityIdentifier("chat.model.\(tier.rawValue)")
                }

                if let loadedTier = model.loadedTier {
                    Divider()
                    Button {
                        Task { await model.unloadModel() }
                    } label: {
                        Label(
                            "Unload \(loadedTier.displayName)",
                            systemImage: "eject"
                        )
                    }
                    .accessibilityIdentifier("chat.model.unload")
                }
            } label: {
                HStack(spacing: AuroraDesign.Space.xs) {
                    Image(systemName: "cpu")
                    Text("Model")
                }
                    .font(.subheadline.weight(.semibold))
                    .fixedSize()
                    .frame(minHeight: 44)
            }
            .accessibilityLabel(modelControlAccessibilityLabel)
            .accessibilityIdentifier("chat.modelSelection")
        }
    }

    private var preferredUnloadedTier: ModelTier {
        if model.modelSelection == .expert, model.expertDeviceIsEligible {
            return .expert
        }
        return .lite
    }

    private func modelMenuTitle(for tier: ModelTier) -> String {
        if model.loadedTier == tier { return tier.displayName }
        return model.runtimeTiers.contains(tier)
            ? "Load \(tier.displayName)"
            : "Set Up \(tier.displayName)"
    }

    private var modelControlAccessibilityLabel: String {
        if let loadedTier = model.loadedTier {
            return "Model: \(loadedTier.displayName)"
        }
        return model.runtimeTiers.contains(preferredUnloadedTier)
            ? "Choose model. \(preferredUnloadedTier.displayName) is ready to load."
            : "Set up model"
    }

    private func activateModel(_ tier: ModelTier) {
        model.modelSelection = tier == .lite ? .lite : .expert
        if model.runtimeTiers.contains(tier) {
            Task { await model.loadModel(tier) }
        } else {
            model.selectedTab = .tools
        }
    }

    @ViewBuilder
    private var modelStatus: some View {
        if case let .failed(_, message) = model.modelRuntimeState {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: AuroraDesign.readableWidth, alignment: .leading)
                .padding(.horizontal, AuroraDesign.Space.md)
                .accessibilityIdentifier("chat.modelStatus")
        }
    }

    private var attachmentMenu: some View {
        VStack(spacing: 0) {
            attachmentMenuRow(title: "Take Photo", systemImage: "camera") {
                takePhoto()
            }
            Divider()
            attachmentMenuRow(
                title: "Choose Photo",
                systemImage: "photo.on.rectangle"
            ) {
                chooseExistingPhoto()
            }
        }
        .frame(width: 250)
        .padding(.vertical, AuroraDesign.Space.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.liteAttachmentSheet")
    }

    private func attachmentMenuRow(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            showsAttachmentMenu = false
            action()
        } label: {
            HStack(spacing: AuroraDesign.Space.sm) {
                Image(systemName: systemImage)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: AuroraDesign.Space.xxs) {
                    Text(title)
                        .font(.body.weight(.medium))
                    if !model.canAttachPhoto {
                        Text("Expert mode")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, AuroraDesign.Space.md)
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.canAttachPhoto ? .primary : .secondary)
        .disabled(!model.canAttachPhoto)
        .accessibilityLabel(
            model.canAttachPhoto ? title : "\(title), Expert mode"
        )
        .accessibilityIdentifier(
            title == "Take Photo"
                ? "chat.liteAttachment.camera"
                : "chat.liteAttachment.photo"
        )
    }

    @ViewBuilder
    private func attachmentPreviewTile(_ attachment: DraftImageAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                guard let data = attachment.imageData else { return }
                previewPhoto = PhotoPreview(
                    data: data,
                    accessibilityLabel: "Attached photo preview"
                )
            } label: {
                attachmentPreviewImage(attachment)
            }
            .buttonStyle(.plain)
            .disabled(attachment.imageData == nil)
            .accessibilityLabel("Preview attached photo")
            .accessibilityIdentifier("chat.attachment.preview")

            Button {
                photoItem = nil
                model.removeAttachment()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2.weight(.semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.72))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 12, y: -12)
            .accessibilityLabel("Remove attached photo")
            .accessibilityIdentifier("chat.attachment.remove")
        }
        .padding(.top, AuroraDesign.Space.xxs)
    }

    @ViewBuilder
    private func attachmentPreviewImage(_ attachment: DraftImageAttachment) -> some View {
        if let data = attachment.thumbnailData,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: AuroraDesign.Radius.compact))
                .accessibilityLabel("Attached photo preview")
        } else if attachment.loadState == .loading {
            ProgressView()
                .frame(width: 64, height: 64)
        } else {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.red)
                .frame(width: 64, height: 64)
        }
    }

    private func attachmentFailureMessage(
        _ attachment: DraftImageAttachment
    ) -> String? {
        if case let .failed(message) = attachment.loadState { return message }
        if case let .failed(message) = attachment.ocrState { return message }
        return nil
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let onPreviewPhoto: (Data) -> Void

    private var visibleNotices: [String] {
        guard let answer = message.answer else { return [] }
        return answer.notices.filter {
            !$0.localizedCaseInsensitiveContains("is available for this incident")
        }
    }

    private var sourceNames: [String] {
        message.answer?.sourceDisplayNames ?? []
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 48)
            }
            VStack(alignment: .leading, spacing: 12) {
                if let thumbnailData = message.thumbnailData,
                   let image = UIImage(data: thumbnailData) {
                    Button {
                        onPreviewPhoto(message.previewImageData ?? thumbnailData)
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240, maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview sent photo")
                    .accessibilityIdentifier("chat.message.photoPreview")
                }
                Text(message.text)
                    .font(.body)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier(
                        message.role == .user ? "chat.question" : "chat.answer"
                    )

                if let answer = message.answer {
                    if let tier = answer.modelTier {
                        Label(
                            tier.displayName,
                            systemImage: answer.visionWasUsed ? "eye.fill" : "cpu"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }

                    if let verification = answer.verificationStatus {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                if answer.verificationIssues.isEmpty {
                                    Text("Every displayed sentence matched its attributed promoted claims.")
                                } else {
                                    ForEach(answer.verificationIssues) { issue in
                                        Text("• \(issue.message)")
                                    }
                                }
                                if answer.corroboratingSourceCount > 0 {
                                    Text("\(answer.corroboratingSourceCount) reviewed source(s) corroborate supported claims. Sources do not verify flagged sentences.")
                                }
                                if let support = answer.supportStatus {
                                    Text("Sentence support: \(support.rawValue.replacingOccurrences(of: "_", with: " ")).")
                                }
                                if let coverage = answer.coverageStatus {
                                    Text("Request coverage: \(coverage.rawValue).")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } label: {
                            Label(
                                verification.displayName,
                                systemImage: verification == .verified
                                    ? "checkmark.shield.fill"
                                    : "exclamationmark.triangle.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                verification == .verified ? .green : .orange
                            )
                        }
                    }

                    if !sourceNames.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sources").font(.caption.weight(.semibold))
                            ForEach(sourceNames, id: \.self) { name in
                                Text(name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("chat.sources")
                    }

                    ForEach(visibleNotices, id: \.self) { notice in
                        Text(notice)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, message.role == .user ? 14 : 0)
            .padding(.vertical, message.role == .user ? 11 : 0)
            .frame(
                maxWidth: message.role == .user ? nil : .infinity,
                alignment: .leading
            )
            .background(
                message.role == .user
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 20)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(
                message.role == .user ? "chat.message.user" : "chat.message.assistant"
            )
            if message.role != .user {
                Spacer(minLength: 20)
            }
        }
    }
}

private struct PhotoPreview: Identifiable {
    let id = UUID()
    let data: Data
    let accessibilityLabel: String
}

private struct PhotoPreviewView: View {
    let preview: PhotoPreview
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = UIImage(data: preview.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(AuroraDesign.Space.md)
                    .accessibilityLabel(preview.accessibilityLabel)
            }
        }
        .accessibilityIdentifier("chat.photoPreview")
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.64))
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding()
            .accessibilityLabel("Close photo preview")
            .accessibilityIdentifier("chat.photoPreview.close")
        }
    }
}
