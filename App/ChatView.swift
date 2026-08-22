import PhotosUI
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showsAttachmentSourceDialog = false
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @FocusState private var composerIsFocused: Bool

    private let starters = [
        "My car will not start",
        "How do I make water safer?",
        "What should I do if I am lost?"
    ]

    var body: some View {
        Group {
            if model.canUseAsk {
                VStack(spacing: 0) {
                    messages
                    composer
                }
            } else {
                modelRequired
            }
        }
        .navigationTitle("Aurora")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Menu {
                    Button("Auto") { model.modelSelection = .automatic }
                    Button("Lite") { model.modelSelection = .lite }
                        .disabled(!model.runtimeTiers.contains(.lite))
                    Button("Expert") { model.modelSelection = .expert }
                        .disabled(model.availability(for: .expert) != .ready)
                } label: {
                    HStack(spacing: 6) {
                        Text(model.modelSelection.displayName)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("Model: \(model.modelSelection.displayName)")
            }
        }
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
    }

    private var modelRequired: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AuroraDesign.Space.lg) {
                ContentUnavailableView {
                    Label("Offline model required", systemImage: "cpu")
                } description: {
                    Text("Install Lite or Expert with its reviewed knowledge package to use Ask. The Field Guide is always available.")
                } actions: {
                    Button { model.selectedTab = .tools } label: {
                        Label("Set up models", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
                    Text("Browse the Field Guide")
                        .font(.title2.bold())
                    Text("Choose an immediate need. No model or download is required.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AuroraDesign.Space.sm) {
                        ForEach(model.fieldGuideChapters) { chapter in
                            Button { model.openManualChapter(chapter.id) } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: chapter.symbol).font(.title2)
                                    Text(chapter.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 92)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("chat.manual-chapter.\(chapter.id)")
                        }
                    }
                }
                .padding(18)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
            }
            .padding(AuroraDesign.Space.md)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("chat.modelRequired")
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: AuroraDesign.Space.lg) {
                    if model.messages.isEmpty {
                        WelcomeCard(starters: starters) { draft = $0 }
                    }
                    ForEach(model.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if model.isThinking {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Thinking offline…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    }
                }
                .frame(maxWidth: AuroraDesign.readableWidth)
                .padding(.horizontal, AuroraDesign.Space.md)
                .padding(.vertical, AuroraDesign.Space.lg)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.messages.count) {
                guard let last = model.messages.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: AuroraDesign.Space.xs) {
            if model.canAttachPhoto,
               let attachment = model.draftImageAttachment {
                HStack(spacing: AuroraDesign.Space.sm) {
                    attachmentPreview(attachment)
                    VStack(alignment: .leading, spacing: AuroraDesign.Space.xxs) {
                        Text(attachmentTitle(attachment))
                            .font(.subheadline.weight(.semibold))
                        Text(attachmentDetail(attachment))
                            .font(.caption)
                            .foregroundStyle(
                                attachmentIsFailed(attachment) ? .red : .secondary
                            )
                    }
                    Spacer()
                    Button("Replace") {
                        showsAttachmentSourceDialog = true
                    }
                    .frame(minHeight: 44)
                    Button("Remove") {
                        photoItem = nil
                        model.removeAttachment()
                    }
                    .frame(minHeight: 44)
                }
                .padding(.horizontal, AuroraDesign.Space.xs)
            }

            if model.canAttachPhoto {
                attachmentOperationFeedback
            }

            HStack(alignment: .bottom, spacing: AuroraDesign.Space.xs) {
                if model.canAttachPhoto {
                    photoAttachmentControl
                }

                TextField("Describe the situation…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.vertical, 11)
                    .focused($composerIsFocused)
                    .accessibilityIdentifier("chat.composer")

                Button {
                    let outgoing = draft
                    draft = ""
                    composerIsFocused = false
                    Task { await model.send(outgoing) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor, in: Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("chat.send")
            }
            .padding(.leading, 2)
            .padding(.trailing, AuroraDesign.Space.xxs)
            .padding(.vertical, AuroraDesign.Space.xxs)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.separator.opacity(0.35), lineWidth: 0.5)
            }

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
        .padding(.top, AuroraDesign.Space.xs)
        .padding(.bottom, AuroraDesign.Space.sm)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var photoAttachmentControl: some View {
        Button {
            showsAttachmentSourceDialog = true
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Attach photo")
    }

    @ViewBuilder
    private var attachmentOperationFeedback: some View {
        switch model.attachmentOperationState {
        case .idle:
            EmptyView()
        case let .loading(message):
            HStack(spacing: AuroraDesign.Space.xs) {
                ProgressView()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, AuroraDesign.Space.xs)
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

    private var canSend: Bool {
        guard !model.isThinking else { return false }
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        guard let attachment = model.draftImageAttachment else { return false }
        return attachment.loadState == .ready && attachment.imageData != nil
    }

    @ViewBuilder
    private func attachmentPreview(_ attachment: DraftImageAttachment) -> some View {
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

    private func attachmentTitle(_ attachment: DraftImageAttachment) -> String {
        switch attachment.loadState {
        case .loading: return "Loading photo"
        case .ready: return "Photo attached"
        case .failed: return "Photo unavailable"
        }
    }

    private func attachmentDetail(_ attachment: DraftImageAttachment) -> String {
        if case let .failed(message) = attachment.loadState { return message }
        switch attachment.ocrState {
        case .pending: return "Preparing offline analysis"
        case let .complete(lines):
            return lines.isEmpty
                ? "Ready for offline analysis"
                : "\(lines.count) text lines found"
        case let .failed(message): return message
        }
    }

    private func attachmentIsFailed(_ attachment: DraftImageAttachment) -> Bool {
        if case .failed = attachment.loadState { return true }
        if case .failed = attachment.ocrState { return true }
        return false
    }
}

private struct WelcomeCard: View {
    let starters: [String]
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AuroraDesign.Space.md) {
            Text("Offline intelligence for the outdoors")
                .font(.title2.weight(.semibold))
            Text("Ask about water, fire, shelter, navigation, first aid, or vehicle trouble. Aurora connects answers to reviewed guidance stored on this device.")
                .foregroundStyle(.secondary)
            ForEach(starters, id: \.self) { starter in
                Button {
                    choose(starter)
                } label: {
                    HStack {
                        Text(starter)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(AuroraDesign.Space.sm)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: AuroraDesign.Radius.compact))
            }
        }
        .padding(.vertical, AuroraDesign.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

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
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Sent photo")
                }
                Text(message.text)
                    .font(.body)
                    .lineSpacing(3)
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
            .frame(maxWidth: message.role == .user ? 560 : .infinity, alignment: .leading)
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
