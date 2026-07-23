import PhotosUI
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showEmergencyHelp = false

    private let starters = [
        "My car will not start",
        "How do I make water safer?",
        "What should I do if I am lost?"
    ]

    var body: some View {
        VStack(spacing: 0) {
            prototypeBanner
            messages
            composer
        }
        .navigationTitle("Aurora")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showEmergencyHelp = true
                } label: {
                    Label("Emergency", systemImage: "sos")
                        .foregroundStyle(.red)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", action: model.resetConversation)
                    .disabled(model.messages.isEmpty)
            }
        }
        .alert("Immediate danger?", isPresented: $showEmergencyHelp) {
            Button("Close", role: .cancel) {}
        } message: {
            Text("Use iPhone Emergency SOS or call the emergency number for your location. Do not wait for a chatbot response.")
        }
        .onChange(of: photoItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                await model.attachImage(data: data)
            }
        }
    }

    private var prototypeBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
            Text("Engineering prototype — not yet clinically or mechanically certified.")
                .font(.caption)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.yellow.opacity(0.85))
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if model.messages.isEmpty {
                        WelcomeCard(starters: starters) { draft = $0 }
                    }
                    ForEach(model.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if model.isThinking {
                        ProgressView("Checking safety and offline sources…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .onChange(of: model.messages.count) {
                guard let last = model.messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
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
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "camera.fill")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Attach photo")

                TextField("Describe the situation…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)

                Button {
                    let outgoing = draft
                    draft = ""
                    Task { await model.send(outgoing) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isThinking)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
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
            Label("Offline incident assistant", systemImage: "mountain.2.fill")
                .font(.title2.bold())
            Text("Ask about vehicle trouble, wilderness basics, navigation, or layperson first aid. Safety rules run before the model.")
                .foregroundStyle(.secondary)
            ForEach(starters, id: \.self) { starter in
                Button(starter) { choose(starter) }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message.text)
                .textSelection(.enabled)

            if let answer = message.answer {
                if answer.usedDeterministicOverride {
                    Label("Safety rule — model bypassed", systemImage: "shield.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                } else if let tier = answer.modelTier {
                    Label(tier.displayName, systemImage: answer.visionWasUsed ? "eye.fill" : "text.bubble.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !answer.sources.isEmpty {
                    DisclosureGroup("Offline sources (\(answer.sources.count))") {
                        ForEach(Array(answer.sources.enumerated()), id: \.element.id) { index, source in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("[\(index + 1)] \(source.title)")
                                    .font(.caption.bold())
                                Text("\(source.organization) · \(source.revision)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                        }
                    }
                    .font(.caption)
                }

                ForEach(answer.notices, id: \.self) { notice in
                    Text(notice)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .background(
            message.role == .user ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }
}
