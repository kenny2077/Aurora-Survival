import PhotosUI
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
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
        .navigationTitle("Ask Aurora")
        .onChange(of: photoItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                await model.attachImage(data: data)
            }
        }
    }

    private var modelRequired: some View {
        ContentUnavailableView {
            Label("Offline model required", systemImage: "cpu")
        } description: {
            Text("Install Lite in Tools to use Ask. The Manual and Maps remain available without a model.")
        } actions: {
            Button {
                model.selectedTab = .tools
            } label: {
                Label("Set up models", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .accessibilityIdentifier("chat.modelRequired")
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
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
                .padding()
            }
            .onChange(of: model.messages.count) {
                guard let last = model.messages.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if model.attachedImageData != nil {
                HStack {
                    Label(
                        model.imageObservations.isEmpty
                            ? "Photo attached"
                            : "\(model.imageObservations.count) text lines found",
                        systemImage: "photo.fill"
                    )
                    .font(.caption)
                    Spacer()
                    Button("Remove", action: model.removeAttachment)
                        .font(.caption)
                }
                .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 10) {
                if model.canAttachPhoto {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "camera.fill")
                            .frame(width: 40, height: 40)
                            .background(.quaternary, in: Circle())
                    }
                    .accessibilityLabel("Attach photo")
                }

                TextField("Describe the situation…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(.quaternary, lineWidth: 1)
                    }
                    .focused($composerIsFocused)
                    .accessibilityIdentifier("chat.composer")

                Button {
                    let outgoing = draft
                    draft = ""
                    composerIsFocused = false
                    Task { await model.send(outgoing) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 36))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isThinking)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("chat.send")
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .padding(.top, 8)
        .background(.bar)
    }
}

private struct WelcomeCard: View {
    let starters: [String]
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your offline field companion", systemImage: "mountain.2.fill")
                .font(.title2.bold())
            Text("Chat naturally about water, fire, shelter, navigation, first aid, or vehicle trouble. Answers connect to the reviewed manual on this device.")
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
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct MessageBubble: View {
    @EnvironmentObject private var model: AppModel
    let message: ChatMessage

    private var visibleNotices: [String] {
        guard let answer = message.answer else { return [] }
        return answer.notices.filter {
            !$0.localizedCaseInsensitiveContains("is available for this incident")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 48)
            }
            VStack(alignment: .leading, spacing: 12) {
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

                    if !answer.manualReferences.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("More in Field Manual")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(answer.manualReferences) { reference in
                                Button {
                                    model.openManual(reference)
                                } label: {
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(reference.sectionTitle)
                                                .font(.subheadline.weight(.semibold))
                                            Text("\(reference.chapterTitle) · \(reference.pageLabel)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 8)
                                        Image(systemName: "arrow.right.circle.fill")
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("chat.manual-link")
                            }
                        }
                        .padding(.top, 4)
                    }

                    ForEach(visibleNotices, id: \.self) { notice in
                        Text(notice)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: message.role == .user ? 560 : .infinity, alignment: .leading)
            .background(
                message.role == .user
                    ? Color.accentColor.opacity(0.12)
                    : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.quaternary, lineWidth: message.role == .user ? 0 : 1)
            }
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
