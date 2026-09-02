#if AURORA_MESH_BETA
import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI

struct MeshChatView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var coordinator = MeshChatCoordinator()
    @State private var showsCreateGroup = false
    @State private var showsScanner = false
    @State private var showsEditName = false

    var body: some View {
        Group {
            if coordinator.hasAcceptedOnboarding {
                meshHome
            } else {
                onboarding
            }
        }
        .navigationTitle("Mesh Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { coordinator.screenDidAppear() }
        .onDisappear { coordinator.screenDidDisappear() }
        .onChange(of: scenePhase) { _, phase in
            coordinator.sceneActivityChanged(isActive: phase == .active)
        }
        .sheet(isPresented: $showsCreateGroup) {
            MeshCreateGroupSheet { coordinator.createGroup(name: $0) }
        }
        .sheet(isPresented: $showsEditName) {
            if let displayName = coordinator.identity?.displayName {
                MeshEditNameSheet(currentName: displayName) {
                    coordinator.updateDisplayName($0)
                }
            }
        }
        .fullScreenCover(isPresented: $showsScanner) {
            MeshInviteScannerScreen { value in
                showsScanner = false
                coordinator.acceptScannedInvitation(value)
            }
            .onAppear { coordinator.screenDidAppear() }
            .onDisappear { coordinator.screenDidDisappear() }
        }
        .alert("Invite verification", isPresented: Binding(
            get: { coordinator.joinVerificationCode != nil },
            set: { if !$0 { coordinator.joinVerificationCode = nil } }
        )) {
            Button("Keep Waiting", role: .cancel) {}
        } message: {
            Text("Ask the inviter to confirm this code: \(coordinator.joinVerificationCode ?? "")")
        }
        .alert("Mesh Chat", isPresented: Binding(
            get: { coordinator.errorMessage != nil },
            set: { if !$0 { coordinator.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(coordinator.errorMessage ?? "")
        }
        .accessibilityIdentifier("mesh.home")
    }

    private var onboarding: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AuroraDesign.Space.lg) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 54))
                    .foregroundStyle(AuroraDesign.river)
                    .accessibilityHidden(true)
                Text("Nearby private groups, without internet")
                    .font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: AuroraDesign.Space.md) {
                    warning("Range is not guaranteed. Concrete, steel, interference, and device position can stop a link.")
                    warning("Every relay must be a current group member with Mesh Chat visible in the foreground.")
                    warning("Locking the phone, leaving Mesh Chat, or switching Aurora inactive stops scanning and relaying.")
                    warning("Mesh Chat does not contact emergency services and is not a substitute for an emergency call or satellite service.")
                }
                Button("I Understand — Open Beta") {
                    coordinator.hasAcceptedOnboarding = true
                    coordinator.start()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("mesh.onboarding.accept")
            }
            .padding(AuroraDesign.Space.lg)
            .frame(maxWidth: AuroraDesign.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func warning(_ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var meshHome: some View {
        List {
            if let identity = coordinator.identity {
                Section {
                    Button { showsEditName = true } label: {
                        HStack(spacing: AuroraDesign.Space.sm) {
                            Text("Name")
                                .foregroundStyle(.primary)
                            Spacer(minLength: AuroraDesign.Space.sm)
                            Text(identity.displayName)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Name, \(identity.displayName)")
                    .accessibilityHint("Edits your Mesh Chat display name")
                    .accessibilityIdentifier("mesh.name.edit")
                }
            }

            if let pending = coordinator.pendingJoin {
                Section("Invite verification") {
                    MeshPendingJoinApproval(
                        pending: pending,
                        approve: coordinator.approvePendingJoin,
                        reject: coordinator.rejectPendingJoin
                    )
                }
            }

            Section {
                HStack {
                    Label(radioLabel, systemImage: radioSymbol)
                    Spacer()
                    Text("\(coordinator.directLinkCount) nearby")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("mesh.radio.status")
                if coordinator.radioState == .denied {
                    Text("Bluetooth access is off. Enable Aurora in Settings to find nearby members.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("mesh.radio.denied")
                } else if coordinator.radioState == .unavailable {
                    Text("Bluetooth is unavailable. Saved groups and local history remain accessible.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("mesh.radio.offline")
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(coordinator.linkDebugStatus)
                    Text("BLE links \(coordinator.directLinkCount) · sent \(coordinator.sentPacketCount) · received \(coordinator.receivedPacketCount) · no-link sends \(coordinator.noLinkSendCount)")
                        .monospacedDigit()
                    if let status = coordinator.inviteTransportStatus {
                        Text(status)
                            .foregroundStyle(.blue)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("mesh.radio.diagnostics")
            }

            Section("Private groups") {
                if coordinator.groups.isEmpty {
                    ContentUnavailableView(
                        "No Mesh Groups",
                        systemImage: "person.3.sequence",
                        description: Text("Create a group or scan a five-minute invite from a nearby Aurora member.")
                    )
                } else {
                    ForEach(coordinator.groups) { group in
                        NavigationLink {
                            MeshGroupChatView(group: group, coordinator: coordinator)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.name).font(.headline)
                                Text("\(reachableCount(in: group)) of \(max(0, group.members.count - 1)) members reachable")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("mesh.group.\(group.id.uuidString)")
                    }
                }
            }

            Section {
                Button { showsCreateGroup = true } label: {
                    Label("Create Group", systemImage: "person.3.fill")
                }
                Button { showsScanner = true } label: {
                    Label("Scan Invite", systemImage: "qrcode.viewfinder")
                }
                .accessibilityIdentifier("mesh.scanInvite")
            }

        }
    }

    private func reachableCount(in group: AuroraMeshGroup) -> Int {
        group.members.filter { coordinator.reachableMemberIDs.contains($0.member.id) }.count
    }

    private var radioLabel: String {
        switch coordinator.radioState {
        case .stopped: "Mesh stopped"
        case .starting: "Starting Bluetooth"
        case .ready: "Mesh visible"
        case .denied: "Bluetooth denied"
        case .unavailable: "Bluetooth unavailable"
        }
    }

    private var radioSymbol: String {
        coordinator.radioState == .ready ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
    }
}

private struct MeshEditNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    let save: (String) -> Void

    init(currentName: String, save: @escaping (String) -> Void) {
        _name = State(initialValue: currentName)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("mesh.name.field")
                } header: {
                    Text("Display name")
                } footer: {
                    Text("This signed name is shown to members of your Mesh groups.")
                }
            }
            .navigationTitle("Edit Name")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(name)
                        dismiss()
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("mesh.name.save")
                }
            }
        }
    }

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed.lengthOfBytes(using: .utf8) <= AuroraMeshLimits.maximumDisplayNameBytes
    }
}

private struct MeshCreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    let create: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Group name", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("mesh.create.name")
                Text("Private groups support up to 20 current members. Any current member can create an invite; only the creator can remove members.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Create Mesh Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create(name); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("mesh.create.confirm")
                }
            }
        }
    }
}

struct MeshConversationMessageContext: Identifiable, Equatable {
    let message: AuroraMeshMessage
    let beginsGroup: Bool
    let endsGroup: Bool

    var id: UUID { message.id }
}

enum MeshConversationItem: Identifiable, Equatable {
    case day(index: Int, date: Date)
    case message(MeshConversationMessageContext)

    var id: String {
        switch self {
        case let .day(index, date):
            "day-\(index)-\(date.timeIntervalSinceReferenceDate)"
        case let .message(context):
            "message-\(context.id.uuidString)"
        }
    }
}

enum MeshDraftCountTone: Equatable {
    case normal
    case warning
    case overLimit
}

struct MeshDraftValidation: Equatable {
    let byteCount: Int
    let canSend: Bool
    let showsCount: Bool
    let tone: MeshDraftCountTone
}

enum MeshConversationLayout {
    static let groupingInterval: TimeInterval = 5 * 60

    static func items(
        messages: [AuroraMeshMessage],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [MeshConversationItem] {
        var items: [MeshConversationItem] = []
        for (index, message) in messages.enumerated() {
            let previous = index > messages.startIndex ? messages[index - 1] : nil
            let next = index + 1 < messages.endIndex ? messages[index + 1] : nil
            if previous == nil || !calendar.isDate(previous!.createdAt, inSameDayAs: message.createdAt) {
                items.append(.day(index: index, date: calendar.startOfDay(for: message.createdAt)))
            }
            items.append(.message(MeshConversationMessageContext(
                message: message,
                beginsGroup: previous.map { !canGroup($0, message, calendar: calendar) } ?? true,
                endsGroup: next.map { !canGroup(message, $0, calendar: calendar) } ?? true
            )))
        }
        return items
    }

    static func dayLabel(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func validateDraft(
        _ text: String,
        maximumBytes: Int = AuroraMeshLimits.maximumTextBytes
    ) -> MeshDraftValidation {
        let byteCount = text.lengthOfBytes(using: .utf8)
        let isBlank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let showsCount = byteCount >= maximumBytes * 3 / 4
        let tone: MeshDraftCountTone
        if byteCount > maximumBytes {
            tone = .overLimit
        } else if byteCount >= maximumBytes * 9 / 10 {
            tone = .warning
        } else {
            tone = .normal
        }
        return MeshDraftValidation(
            byteCount: byteCount,
            canSend: !isBlank && byteCount <= maximumBytes,
            showsCount: showsCount,
            tone: tone
        )
    }

    private static func canGroup(
        _ earlier: AuroraMeshMessage,
        _ later: AuroraMeshMessage,
        calendar: Calendar
    ) -> Bool {
        guard earlier.senderID == later.senderID,
              calendar.isDate(earlier.createdAt, inSameDayAs: later.createdAt)
        else { return false }
        let gap = later.createdAt.timeIntervalSince(earlier.createdAt)
        return gap >= 0 && gap <= groupingInterval
    }
}

private struct MeshGroupChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let group: AuroraMeshGroup
    @ObservedObject var coordinator: MeshChatCoordinator
    @State private var draft = ""
    @State private var inviteText: String?
    @State private var showsDetails = false
    @State private var isNearBottom = true
    @State private var unreadMessageCount = 0
    @State private var scrollRequest = 0
    @State private var isSending = false
    @FocusState private var composerIsFocused: Bool

    private let bottomAnchor = "mesh.conversation.bottom"

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if messages.isEmpty {
                            emptyConversation
                                .frame(minHeight: max(0, geometry.size.height - 80))
                        } else {
                            ForEach(conversationItems) { item in
                                switch item {
                                case let .day(_, date):
                                    MeshDaySeparator(date: date)
                                case let .message(context):
                                    MeshMessageRow(
                                        context: context,
                                        isOwn: context.message.senderID == coordinator.identity?.id,
                                        senderName: senderName(for: context.message),
                                        maximumBubbleWidth: min(geometry.size.width * 0.78, 520),
                                        colorScheme: colorScheme
                                    )
                                }
                            }
                        }
                        Color.clear.frame(height: 1).id(bottomAnchor)
                    }
                    .frame(maxWidth: AuroraDesign.readableWidth)
                    .padding(.horizontal, AuroraDesign.Space.md)
                    .padding(.vertical, AuroraDesign.Space.sm)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { composerIsFocused = false })
                .onScrollGeometryChange(for: Bool.self) { scroll in
                    scroll.contentOffset.y + scroll.containerSize.height
                        >= scroll.contentSize.height - 80
                } action: { _, nearBottom in
                    isNearBottom = nearBottom
                    if nearBottom { unreadMessageCount = 0 }
                }
                .overlay(alignment: .bottom) {
                    if unreadMessageCount > 0 {
                        Button {
                            unreadMessageCount = 0
                            scrollToBottom(proxy, animated: true)
                        } label: {
                            Label(
                                unreadMessageCount == 1
                                    ? "1 new message"
                                    : "\(unreadMessageCount) new messages",
                                systemImage: "arrow.down"
                            )
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, AuroraDesign.Space.md)
                            .padding(.vertical, AuroraDesign.Space.xs)
                            .background(.regularMaterial, in: Capsule())
                            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, AuroraDesign.Space.sm)
                        .accessibilityIdentifier("mesh.messages.new")
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .onAppear {
                    Task { @MainActor in
                        await Task.yield()
                        scrollToBottom(proxy, animated: false)
                    }
                }
                .onChange(of: messages.count) { oldCount, newCount in
                    guard newCount > oldCount else { return }
                    let addedCount = newCount - oldCount
                    let newestIsOwn = messages.last?.senderID == coordinator.identity?.id
                    if isNearBottom || newestIsOwn {
                        scrollToBottom(proxy, animated: true)
                    } else {
                        unreadMessageCount += addedCount
                    }
                }
                .onChange(of: scrollRequest) { _, _ in
                    scrollToBottom(proxy, animated: true)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(group.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(nearbyLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("mesh.group.header")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsDetails = true } label: {
                    Image(systemName: "info.circle")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Group details")
            }
        }
        .sheet(isPresented: $showsDetails) {
            MeshGroupDetailsView(
                group: group,
                coordinator: coordinator,
                inviteText: $inviteText,
                onDeleted: { dismiss() }
            )
        }
        .sheet(isPresented: Binding(get: { inviteText != nil }, set: { if !$0 { inviteText = nil } })) {
            if let inviteText {
                MeshInviteSheet(inviteText: inviteText, coordinator: coordinator)
            }
        }
        .onAppear { coordinator.screenDidAppear() }
        .onDisappear { coordinator.screenDidDisappear() }
        .onChange(of: coordinator.groups.map(\.id)) { _, groupIDs in
            if !groupIDs.contains(group.id) {
                showsDetails = false
                dismiss()
            }
        }
    }

    private var messages: [AuroraMeshMessage] {
        coordinator.messagesByGroup[group.id] ?? []
    }

    private var conversationItems: [MeshConversationItem] {
        MeshConversationLayout.items(messages: messages)
    }

    private var nearbyCount: Int {
        group.members.filter {
            $0.member.id != coordinator.identity?.id
                && coordinator.reachableMemberIDs.contains($0.member.id)
        }.count
    }

    private var nearbyLabel: String {
        switch nearbyCount {
        case 0: "No one nearby"
        case 1: "1 nearby"
        default: "\(nearbyCount) nearby"
        }
    }

    private var emptyConversation: some View {
        VStack(spacing: AuroraDesign.Space.sm) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(AuroraDesign.river)
            Text("No messages yet")
                .font(.title3.weight(.semibold))
            Text("Send the first message. Everyone must keep Mesh Chat visible to receive and relay it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(AuroraDesign.Space.lg)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mesh.messages.empty")
    }

    private var composer: some View {
        let validation = MeshConversationLayout.validateDraft(draft)
        return VStack(spacing: AuroraDesign.Space.xxs) {
            if validation.showsCount {
                HStack {
                    Spacer()
                    Text("\(validation.byteCount) / \(AuroraMeshLimits.maximumTextBytes) bytes")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(byteCountColor(validation.tone))
                        .accessibilityIdentifier("mesh.message.byteCount")
                }
                .padding(.horizontal, AuroraDesign.Space.xs)
            }
            HStack(alignment: .bottom, spacing: AuroraDesign.Space.xs) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerIsFocused)
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, AuroraDesign.Space.md)
                    .padding(.vertical, 11)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .accessibilityIdentifier("mesh.message.composer")
                Button { sendDraft() } label: {
                    Image(systemName: "arrow.up")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(validation.canSend && !isSending ? .white : .secondary)
                        .frame(width: 44, height: 44)
                        .background(
                            validation.canSend && !isSending
                                ? AnyShapeStyle(AuroraDesign.aurora(colorScheme: colorScheme))
                                : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!validation.canSend || isSending)
                .accessibilityLabel("Send message")
                .accessibilityIdentifier("mesh.message.send")
            }
        }
        .frame(maxWidth: AuroraDesign.readableWidth)
        .padding(.horizontal, AuroraDesign.Space.md)
        .padding(.top, AuroraDesign.Space.xs)
        .padding(.bottom, AuroraDesign.Space.xs)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func sendDraft() {
        let outgoing = draft
        guard MeshConversationLayout.validateDraft(outgoing).canSend else { return }
        isSending = true
        Task {
            let sent = await coordinator.send(outgoing, to: group.id)
            isSending = false
            if sent {
                if draft == outgoing { draft = "" }
                unreadMessageCount = 0
                scrollRequest += 1
            }
        }
    }

    private func senderName(for message: AuroraMeshMessage) -> String {
        coordinator.displayName(
            for: message.senderID,
            groupID: group.id,
            fallback: group.members.first(where: {
                $0.member.id == message.senderID
            })?.member.displayName ?? "Member"
        )
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated && !reduceMotion {
            withAnimation(.smooth(duration: 0.24)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    private func byteCountColor(_ tone: MeshDraftCountTone) -> Color {
        switch tone {
        case .normal: .secondary
        case .warning: .orange
        case .overLimit: .red
        }
    }
}

private struct MeshMessageRow: View {
    let context: MeshConversationMessageContext
    let isOwn: Bool
    let senderName: String
    let maximumBubbleWidth: CGFloat
    let colorScheme: ColorScheme

    private var message: AuroraMeshMessage { context.message }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isOwn { Spacer(minLength: 44) }
            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                if !isOwn, context.beginsGroup {
                    Text(senderName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AuroraDesign.river)
                        .padding(.leading, 4)
                        .accessibilityIdentifier("mesh.message.sender")
                }
                Text(message.text)
                    .font(.body)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .foregroundStyle(isOwn ? Color.white : Color.primary)
                    .background(bubbleStyle, in: bubbleShape)
                if context.endsGroup {
                    HStack(spacing: 4) {
                        Text(message.createdAt, format: .dateTime.hour().minute())
                        if isOwn {
                            Image(systemName: deliverySymbol)
                            Text(deliveryText)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier(isOwn ? "mesh.message.delivery" : "mesh.message.time")
                }
            }
            .frame(maxWidth: maximumBubbleWidth, alignment: isOwn ? .trailing : .leading)
            if !isOwn { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
        .padding(.top, context.beginsGroup ? AuroraDesign.Space.sm : 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("mesh.message.\(message.id.uuidString)")
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: !isOwn && context.endsGroup ? 5 : 18,
            bottomTrailingRadius: isOwn && context.endsGroup ? 5 : 18,
            topTrailingRadius: 18
        )
    }

    private var bubbleStyle: AnyShapeStyle {
        isOwn
            ? AnyShapeStyle(AuroraDesign.aurora(colorScheme: colorScheme))
            : AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
    }

    private var deliverySymbol: String {
        switch message.deliveryState {
        case .sending: "clock"
        case .relayed: "arrow.triangle.branch"
        case .delivered: "checkmark.circle.fill"
        }
    }

    private var deliveryText: String {
        switch message.deliveryState {
        case .sending: "Sending"
        case .relayed: "Relayed"
        case let .delivered(received, expected): "Delivered \(received) of \(expected)"
        }
    }

    private var accessibilityText: String {
        var parts = [isOwn ? "You" : senderName, message.text]
        if context.endsGroup {
            parts.append(message.createdAt.formatted(date: .omitted, time: .shortened))
            if isOwn { parts.append(deliveryText) }
        }
        return parts.joined(separator: ". ")
    }
}

private struct MeshDaySeparator: View {
    let date: Date

    var body: some View {
        Text(MeshConversationLayout.dayLabel(for: date))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, AuroraDesign.Space.sm)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.84), in: Capsule())
            .padding(.vertical, AuroraDesign.Space.sm)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("mesh.message.day")
    }
}

private struct MeshGroupDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let group: AuroraMeshGroup
    @ObservedObject var coordinator: MeshChatCoordinator
    @Binding var inviteText: String?
    let onDeleted: () -> Void
    @State private var showsDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deletionError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Members") {
                    ForEach(group.members, id: \.member.id) { grant in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(coordinator.displayName(
                                    for: grant.member.id,
                                    groupID: group.id,
                                    fallback: grant.member.displayName
                                ))
                                Text(grant.member.shortFingerprint).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if group.creatorID == coordinator.identity?.id,
                               grant.member.id != coordinator.identity?.id {
                                Button("Remove", role: .destructive) {
                                    coordinator.removeMember(grant.member.id, groupID: group.id)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Section {
                    Button("Invite Member") {
                        Task {
                            inviteText = await coordinator.invitationText(groupID: group.id)
                            dismiss()
                        }
                    }
                    Button("Delete Local History", role: .destructive) {
                        coordinator.deleteHistory(groupID: group.id)
                    }
                    if group.creatorID == coordinator.identity?.id {
                        Button(role: .destructive) {
                            showsDeleteConfirmation = true
                        } label: {
                            if isDeleting {
                                ProgressView()
                            } else {
                                Text("Delete Group")
                            }
                        }
                        .disabled(isDeleting)
                        .accessibilityIdentifier("mesh.group.delete")
                    } else {
                        Button("Leave Group", role: .destructive) {
                            coordinator.leaveGroup(groupID: group.id)
                            dismiss()
                        }
                    }
                } footer: {
                    Text("Deleting local history creates tombstones so seven-day catch-up cannot restore those messages.")
                }
            }
            .navigationTitle("Group Details")
            .toolbar { Button("Done") { dismiss() } }
        }
        .confirmationDialog(
            "Delete Group?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Group for Everyone", role: .destructive) {
                Task {
                    isDeleting = true
                    let deleted = await coordinator.deleteGroup(groupID: group.id)
                    isDeleting = false
                    if deleted {
                        dismiss()
                        onDeleted()
                    } else {
                        deletionError = coordinator.errorMessage ?? "Mesh Chat could not delete this group."
                        coordinator.errorMessage = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the group and local history. Current members will remove it when they receive the signed deletion.")
        }
        .alert("Couldn’t Delete Group", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionError ?? "")
        }
        .onAppear { coordinator.screenDidAppear() }
        .onDisappear { coordinator.screenDidDisappear() }
    }
}

private struct MeshInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let inviteText: String
    @ObservedObject var coordinator: MeshChatCoordinator

    var body: some View {
        NavigationStack {
            VStack(spacing: AuroraDesign.Space.lg) {
                if let image = qrImage {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                        .frame(maxWidth: 300).accessibilityLabel("Five-minute Mesh Chat invitation QR code")
                }
                if let pending = coordinator.pendingJoin {
                    MeshPendingJoinApproval(
                        pending: pending,
                        approve: coordinator.approvePendingJoin,
                        reject: coordinator.rejectPendingJoin
                    )
                } else {
                    Text("Keep both devices on this screen and compare the six-digit code before approving. The QR code contains no group key.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                VStack(spacing: 3) {
                    Text(coordinator.inviteTransportStatus ?? coordinator.linkDebugStatus)
                    Text("BLE links \(coordinator.directLinkCount) · sent \(coordinator.sentPacketCount) · received \(coordinator.receivedPacketCount) · no-link sends \(coordinator.noLinkSendCount)")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Invite Member")
            .toolbar { Button("Done") { dismiss() } }
        }
        .onAppear { coordinator.screenDidAppear() }
        .onDisappear { coordinator.screenDidDisappear() }
    }

    private var qrImage: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(inviteText.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct MeshPendingJoinApproval: View {
    let pending: MeshChatCoordinator.PendingJoin
    let approve: () -> Void
    let reject: () -> Void

    var body: some View {
        VStack(spacing: AuroraDesign.Space.md) {
            Text("Approve \(pending.displayName)?")
                .font(.headline)
            Text(pending.verificationCode)
                .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                .accessibilityLabel("Verification code \(pending.verificationCode)")
            Text("Confirm both devices show this code. Approval adds this identity to the private group.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Reject", role: .cancel, action: reject)
                    .buttonStyle(.bordered)
                Button("Codes Match", action: approve)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("mesh.invite.approve")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AuroraDesign.Space.sm)
    }
}

private enum MeshScannerState: Equatable {
    case requestingPermission
    case running
    case denied
    case unavailable
}

private struct MeshInviteScannerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var state: MeshScannerState = .requestingPermission
    let onCode: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            let guideSize = min(proxy.size.width, proxy.size.height) * 0.62
            ZStack {
                MeshInviteScanner(state: $state, onCode: onCode)
                    .ignoresSafeArea()

                if state == .running {
                    RoundedRectangle(cornerRadius: guideSize * 0.08)
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                        .frame(width: guideSize, height: guideSize)
                        .shadow(color: .black.opacity(0.65), radius: 4)
                        .accessibilityHidden(true)
                } else {
                    Color.black.opacity(0.82).ignoresSafeArea()
                }

                VStack(spacing: AuroraDesign.Space.lg) {
                    HStack {
                        Button { dismiss() } label: {
                            Label("Close", systemImage: "xmark")
                                .font(.headline)
                                .padding(.horizontal, AuroraDesign.Space.md)
                                .padding(.vertical, AuroraDesign.Space.sm)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .tint(.white)
                        .accessibilityIdentifier("mesh.scanner.close")
                        Spacer()
                    }
                    Spacer()
                    if state == .running {
                        Text("Center an Aurora Mesh invite inside the guide")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(AuroraDesign.Space.md)

                if state != .running {
                    scannerStatus
                        .padding(AuroraDesign.Space.lg)
                        .frame(maxWidth: AuroraDesign.readableWidth)
                }
            }
        }
        .background(.black)
        .statusBarHidden(true)
        .accessibilityIdentifier("mesh.scanner.fullScreen")
    }

    @ViewBuilder
    private var scannerStatus: some View {
        VStack(spacing: AuroraDesign.Space.md) {
            switch state {
            case .requestingPermission:
                ProgressView().tint(.white)
                Text("Preparing camera…")
            case .denied:
                Image(systemName: "camera.fill").font(.largeTitle)
                Text("Camera access is off")
                    .font(.title2.bold())
                Text("Allow Aurora to use the camera in Settings, then reopen the scanner.")
                    .foregroundStyle(.secondary)
            case .unavailable:
                Image(systemName: "camera.fill").font(.largeTitle)
                Text("Camera unavailable")
                    .font(.title2.bold())
                Text("Aurora could not start this device’s camera. Close the scanner and try again.")
                    .foregroundStyle(.secondary)
            case .running:
                EmptyView()
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mesh.scanner.status")
    }
}

private struct MeshInviteScanner: UIViewControllerRepresentable {
    @Binding var state: MeshScannerState
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(state: $state, onCode: onCode)
    }

    func makeUIViewController(context: Context) -> MeshScannerViewController {
        let controller = MeshScannerViewController()
        controller.onCode = context.coordinator.onCode
        controller.onStateChange = { context.coordinator.state.wrappedValue = $0 }
        return controller
    }

    func updateUIViewController(_ uiViewController: MeshScannerViewController, context: Context) {
        context.coordinator.state = $state
    }

    final class Coordinator {
        var state: Binding<MeshScannerState>
        let onCode: (String) -> Void

        init(state: Binding<MeshScannerState>, onCode: @escaping (String) -> Void) {
            self.state = state
            self.onCode = onCode
        }
    }
}

private final class MeshScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onStateChange: ((MeshScannerState) -> Void)?
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.example.AuroraSurvivalAgent.mesh.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var delivered = false
    private var configured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            updateState(.requestingPermission)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configure()
                } else {
                    self?.updateState(.denied)
                }
            }
        case .denied, .restricted:
            updateState(.denied)
        @unknown default:
            updateState(.unavailable)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
        guard let orientation = view.window?.windowScene?.interfaceOrientation,
              let connection = preview?.connection
        else { return }
        let angle: CGFloat = switch orientation {
        case .portrait: 90
        case .portraitUpsideDown: 270
        case .landscapeLeft: 180
        default: 0
        }
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        sessionQueue.async { [weak self] in
            guard let self, !self.configured,
                  let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input)
            else {
                self?.updateState(.unavailable)
                return
            }
            self.session.beginConfiguration()
            self.session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard self.session.canAddOutput(output) else {
                self.session.commitConfiguration()
                self.updateState(.unavailable)
                return
            }
            self.session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            self.session.commitConfiguration()
            self.configured = true
            self.session.startRunning()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.viewIfLoaded?.window != nil else { return }
                let preview = AVCaptureVideoPreviewLayer(session: self.session)
                preview.videoGravity = .resizeAspectFill
                preview.frame = self.view.bounds
                self.view.layer.insertSublayer(preview, at: 0)
                self.preview = preview
                self.updateState(.running)
            }
        }
    }

    private func updateState(_ state: MeshScannerState) {
        DispatchQueue.main.async { [weak self] in self?.onStateChange?(state) }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !delivered,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue,
              value.hasPrefix("aurora-mesh://invite/")
        else { return }
        delivered = true
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        onCode?(value)
    }
}
#endif
