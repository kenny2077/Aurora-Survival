#if AURORA_MESH_BETA
import Combine
import Foundation
import SwiftUI

@MainActor
final class MeshChatCoordinator: ObservableObject {
    struct PendingJoin: Identifiable {
        let id: UUID
        let request: AuroraMeshJoinRequest
        let displayName: String
        let verificationCode: String
    }

    @Published private(set) var identity: AuroraMeshIdentity?
    @Published private(set) var groups: [AuroraMeshGroup] = []
    @Published private(set) var messagesByGroup: [UUID: [AuroraMeshMessage]] = [:]
    @Published private(set) var reachableMemberIDs: Set<String> = []
    @Published private(set) var displayNamesByGroup: [UUID: [String: String]] = [:]
    @Published private(set) var radioState: MeshBLELink.RadioState = .stopped
    @Published private(set) var directLinkCount = 0
    @Published private(set) var linkDebugStatus = "Stopped"
    @Published private(set) var sentPacketCount = 0
    @Published private(set) var receivedPacketCount = 0
    @Published private(set) var noLinkSendCount = 0
    @Published private(set) var inviteTransportStatus: String?
    @Published var errorMessage: String?
    @Published var pendingJoin: PendingJoin?
    @Published var joinVerificationCode: String?

    @AppStorage("aurora.mesh.beta.onboarding.complete") var hasAcceptedOnboarding = false

    private let vault = MeshKeychainVault()
    private var store: AuroraMeshStore?
    private var engine: AuroraMeshEngine?
    private var link: MeshBLELink?
    private var subscriptions: Set<AnyCancellable> = []
    private var activeInvitation: AuroraMeshInvitation?
    private var activeJoinContext: AuroraMeshJoinContext?
    private var inviteHelloTask: Task<Void, Never>?
    private var inviteApprovalTask: Task<Void, Never>?
    private var delayedStopTask: Task<Void, Never>?
    private var visibleScreenCount = 0
    private var meshStarted = false
    private var presenceTask: Task<Void, Never>?
    private var acknowledgementTasks: [UUID: Task<Void, Never>] = [:]

    init() {
        if ProcessInfo.processInfo.environment["AURORA_UI_RESET_MESH_ONBOARDING"] == "1" {
            UserDefaults.standard.removeObject(forKey: "aurora.mesh.beta.onboarding.complete")
        }
        do {
            let privateIdentity = try vault.loadOrCreateIdentity(displayName: Self.defaultDisplayName)
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("AuroraMesh", isDirectory: true)
            let store = try AuroraMeshStore(databaseURL: directory.appendingPathComponent("mesh-v1.sqlite"))
            var keys: [UUID: [Int: Data]] = [:]
            for group in try store.groups() {
                let recordedEpochs = try store.keyEpochs(groupID: group.id)
                for epoch in recordedEpochs.isEmpty ? [group.epoch] : recordedEpochs {
                    if let key = try vault.groupKey(groupID: group.id, epoch: epoch) {
                        keys[group.id, default: [:]][epoch] = key
                    }
                }
            }
            let engine = try AuroraMeshEngine(identity: privateIdentity, store: store, groupKeys: keys)
            let link = MeshBLELink(identityID: privateIdentity.identity.id)
            self.identity = privateIdentity.identity
            self.store = store
            self.engine = engine
            self.link = link
            link.onPacket = { [weak self] data in self?.receive(data) }
            link.$state.sink { [weak self] in self?.radioState = $0 }.store(in: &subscriptions)
            link.$debugStatus.sink { [weak self] in self?.linkDebugStatus = $0 }.store(in: &subscriptions)
            link.$sentPacketCount.sink { [weak self] in self?.sentPacketCount = $0 }.store(in: &subscriptions)
            link.$receivedPacketCount.sink { [weak self] in self?.receivedPacketCount = $0 }.store(in: &subscriptions)
            link.$noLinkSendCount.sink { [weak self] in self?.noLinkSendCount = $0 }.store(in: &subscriptions)
            link.$directLinkCount.sink { [weak self] count in
                guard let self else { return }
                let hadLinks = self.directLinkCount > 0
                self.directLinkCount = count
                if count > 0, !hadLinks {
                    self.announcePresence()
                    self.relayPendingTerminations()
                }
            }.store(in: &subscriptions)
            Task { await restoreHistoryAndRefresh() }
        } catch {
            errorMessage = "Mesh Chat could not open its protected local store."
        }
    }

    func start() {
        delayedStopTask?.cancel()
        delayedStopTask = nil
        guard !meshStarted else { return }
        meshStarted = true
        link?.start()
        startPresenceLoop()
        Task {
            await performGroupMaintenance()
            await relayPendingTerminationsNow()
        }
        if activeInvitation != nil, activeJoinContext != nil {
            startInviteHelloRetry()
        }
    }

    func stop() {
        meshStarted = false
        presenceTask?.cancel()
        presenceTask = nil
        acknowledgementTasks.values.forEach { $0.cancel() }
        acknowledgementTasks.removeAll()
        inviteHelloTask?.cancel()
        inviteHelloTask = nil
        inviteApprovalTask?.cancel()
        inviteApprovalTask = nil
        link?.stop()
    }

    func screenDidAppear() {
        visibleScreenCount += 1
        delayedStopTask?.cancel()
        delayedStopTask = nil
        if hasAcceptedOnboarding {
            start()
        }
    }

    func screenDidDisappear() {
        visibleScreenCount = max(0, visibleScreenCount - 1)
        guard visibleScreenCount == 0 else { return }
        delayedStopTask?.cancel()
        delayedStopTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, self.visibleScreenCount == 0 else { return }
            self.stop()
            self.delayedStopTask = nil
        }
    }

    func sceneActivityChanged(isActive: Bool) {
        if isActive, visibleScreenCount > 0, hasAcceptedOnboarding {
            start()
        } else if !isActive {
            stop()
        }
    }

    func createGroup(name: String) {
        Task {
            do {
                guard let engine else { return }
                let group = try await engine.createGroup(name: name)
                if let key = await engine.keyMaterial(groupID: group.id, epoch: group.epoch) {
                    try vault.saveGroupKey(key, groupID: group.id, epoch: group.epoch)
                    try store?.recordKeyEpoch(groupID: group.id, epoch: group.epoch)
                }
                await refreshSnapshot()
            } catch {
                errorMessage = message(for: error)
            }
        }
    }

    func updateDisplayName(_ displayName: String) {
        let previousName = identity?.displayName
        Task {
            do {
                let updatedIdentity = try vault.updateDisplayName(displayName)
                guard let events = try await engine?.updateIdentity(updatedIdentity) else { return }
                identity = updatedIdentity.identity
                await handle(events)
                await refreshSnapshot()
            } catch {
                if let previousName {
                    _ = try? vault.updateDisplayName(previousName)
                }
                errorMessage = message(for: error)
            }
        }
    }

    func displayName(for memberID: String, groupID: UUID, fallback: String) -> String {
        if memberID == identity?.id { return identity?.displayName ?? fallback }
        return displayNamesByGroup[groupID]?[memberID] ?? fallback
    }

    func send(_ text: String, to groupID: UUID) async -> Bool {
        do {
            guard let engine else { return false }
            let events = try await engine.sendText(text, groupID: groupID)
            await handle(events)
            await refreshSnapshot()
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func deleteHistory(groupID: UUID) {
        Task {
            do {
                try await engine?.deleteLocalHistory(groupID: groupID)
                if let removed = await engine?.discardHistoricalKeys(groupID: groupID) {
                    for epoch in removed {
                        try vault.deleteGroupKey(groupID: groupID, epoch: epoch)
                        try store?.deleteKeyEpoch(groupID: groupID, epoch: epoch)
                    }
                }
                await refreshSnapshot()
            } catch {
                errorMessage = message(for: error)
            }
        }
    }

    func removeMember(_ memberID: String, groupID: UUID) {
        Task {
            do {
                guard let events = try await engine?.removeMember(memberID: memberID, groupID: groupID) else { return }
                await handle(events)
                await refreshSnapshot()
            } catch { errorMessage = message(for: error) }
        }
    }

    func leaveGroup(groupID: UUID) {
        Task {
            do {
                guard let events = try await engine?.leaveGroup(groupID: groupID) else { return }
                await handle(events)
                await refreshSnapshot()
            } catch { errorMessage = message(for: error) }
        }
    }

    func deleteGroup(groupID: UUID) async -> Bool {
        do {
            guard let events = try await engine?.endGroup(groupID: groupID) else { return false }
            await handle(events)
            await performGroupMaintenance()
            await refreshSnapshot()
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func invitationText(groupID: UUID) async -> String? {
        do {
            guard let invitation = try await engine?.makeInvitation(groupID: groupID) else { return nil }
            let data = try Self.encoder.encode(invitation)
            return "aurora-mesh://invite/" + Self.base64URL(data)
        } catch {
            errorMessage = message(for: error)
            return nil
        }
    }

    func acceptScannedInvitation(_ value: String) {
        Task {
            do {
                guard let encoded = value.components(separatedBy: "aurora-mesh://invite/").last,
                      let data = Self.dataFromBase64URL(encoded),
                      data.count <= AuroraMeshLimits.maximumControlPayloadBytes,
                      let engine
                else { throw AuroraMeshError.invalidPacket }
                let invitation = try Self.decoder.decode(AuroraMeshInvitation.self, from: data)
                let context = try await engine.makeJoinContext(for: invitation)
                activeInvitation = invitation
                activeJoinContext = context
                joinVerificationCode = context.verificationCode
                startInviteHelloRetry()
            } catch {
                errorMessage = message(for: error)
            }
        }
    }

    func approvePendingJoin() {
        guard let pendingJoin else { return }
        Task {
            do {
                guard let result = try await engine?.approve(pendingJoin.request) else { return }
                startInviteApprovalRetry(
                    invitationID: result.approval.invitationID,
                    payload: try Self.encoder.encode(result.approval)
                )
                await handle(result.events)
                self.pendingJoin = nil
                await refreshSnapshot()
            } catch {
                errorMessage = message(for: error)
            }
        }
    }

    func rejectPendingJoin() {
        pendingJoin = nil
    }

    private func receive(_ data: Data) {
        Task {
            do {
                let packet = try AuroraMeshWireCodec.decode(data)
                switch packet.kind {
                case .groupEnvelope:
                    guard let engine else { return }
                    let events = try await engine.ingest(packet)
                    await handle(events)
                    await performGroupMaintenance()
                    await refreshSnapshot()
                case .inviteHello:
                    let request = try Self.decoder.decode(AuroraMeshJoinRequest.self, from: packet.payload)
                    guard let code = try await engine?.verificationCode(for: request) else { return }
                    inviteTransportStatus = "Invite request received from \(request.joiner.displayName)"
                    pendingJoin = PendingJoin(
                        id: request.invitationID,
                        request: request,
                        displayName: request.joiner.displayName,
                        verificationCode: code
                    )
                case .inviteApproval:
                    guard let invitation = activeInvitation,
                          let context = activeJoinContext,
                          let engine
                    else { return }
                    let approval = try Self.decoder.decode(AuroraMeshInviteApproval.self, from: packet.payload)
                    let group = try await engine.consume(approval, invitation: invitation, context: context)
                    inviteHelloTask?.cancel()
                    inviteHelloTask = nil
                    inviteTransportStatus = "Invitation approved"
                    if let key = await engine.keyMaterial(groupID: group.id, epoch: group.epoch) {
                        try vault.saveGroupKey(key, groupID: group.id, epoch: group.epoch)
                        try store?.recordKeyEpoch(groupID: group.id, epoch: group.epoch)
                    }
                    activeInvitation = nil
                    activeJoinContext = nil
                    joinVerificationCode = nil
                    await refreshSnapshot()
                }
            } catch AuroraMeshError.duplicateMessage {
                return
            } catch AuroraMeshError.sequenceReplay {
                return
            } catch AuroraMeshError.invitationNotFound {
                return
            } catch AuroraMeshError.unauthorized {
                return
            } catch {
                errorMessage = message(for: error)
            }
        }
    }

    private func handle(_ events: [AuroraMeshEngineEvent]) async {
        for event in events {
            switch event {
            case let .transmit(packet):
                if let data = try? AuroraMeshWireCodec.encode(packet) {
                    if link?.broadcast(data) == true, let groupID = groupID(for: packet) {
                        await engine?.markRelayed(messageID: packet.messageID, groupID: groupID)
                    }
                }
            case let .acknowledgementPending(groupID):
                scheduleAcknowledgement(groupID: groupID)
            case .receivedMessage, .deliveryChanged:
                break
            }
        }
    }

    private func scheduleAcknowledgement(groupID: UUID) {
        guard acknowledgementTasks[groupID] == nil else { return }
        acknowledgementTasks[groupID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            do {
                let events = try await self.engine?.flushAcknowledgements(groupID: groupID) ?? []
                self.acknowledgementTasks[groupID] = nil
                await self.handle(events)
            } catch {
                self.acknowledgementTasks[groupID] = nil
                self.errorMessage = self.message(for: error)
            }
        }
    }

    private func startPresenceLoop() {
        guard presenceTask == nil else { return }
        announcePresence()
        presenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(AuroraMeshLimits.presenceInterval))
                guard !Task.isCancelled, let self else { return }
                self.announcePresence()
                await self.performGroupMaintenance()
            }
        }
    }

    private func announcePresence() {
        Task {
            do {
                guard let packets = try await engine?.makeSyncSummaryPackets() else { return }
                await handle(packets.map(AuroraMeshEngineEvent.transmit))
                await refreshSnapshot()
            } catch {
                errorMessage = message(for: error)
            }
        }
    }

    private func relayPendingTerminations() {
        Task { await relayPendingTerminationsNow() }
    }

    private func relayPendingTerminationsNow() async {
        do {
            guard let packets = try await engine?.pendingTerminationPackets() else { return }
            for packet in packets {
                guard let data = try? AuroraMeshWireCodec.encode(packet) else { continue }
                _ = link?.broadcast(data)
            }
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func performGroupMaintenance() async {
        do {
            guard let engine else { return }
            for cleanup in try await engine.pendingGroupCleanups() {
                for epoch in cleanup.epochs {
                    try vault.deleteGroupKey(groupID: cleanup.groupID, epoch: epoch)
                }
                try await engine.completeGroupCleanup(cleanup)
            }
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func groupID(for packet: AuroraMeshWirePacket) -> UUID? {
        groups.first(where: { group in
            guard let key = try? vault.groupKey(groupID: group.id, epoch: group.epoch) else { return false }
            return AuroraMeshCrypto.groupTag(groupKey: key, epoch: group.epoch) == packet.groupTag
        })?.id
    }

    private func startInviteHelloRetry() {
        guard let invitation = activeInvitation,
              let context = activeJoinContext,
              let payload = try? Self.encoder.encode(context.request)
        else { return }
        inviteHelloTask?.cancel()
        inviteHelloTask = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled, Date() < invitation.expiresAt {
                guard let self else { return }
                attempt += 1
                let sent = self.transmitControl(
                    kind: .inviteHello,
                    id: context.request.invitationID,
                    payload: payload
                )
                self.inviteTransportStatus = sent
                    ? "Invite request sent over BLE (attempt \(attempt))"
                    : "Waiting for a nearby writable BLE link (attempt \(attempt))"
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled, let self else { return }
            self.inviteTransportStatus = "Invitation expired before approval"
            self.joinVerificationCode = nil
        }
    }

    private func startInviteApprovalRetry(invitationID: UUID, payload: Data) {
        inviteApprovalTask?.cancel()
        inviteApprovalTask = Task { [weak self] in
            for attempt in 1...12 {
                guard !Task.isCancelled, let self else { return }
                let sent = self.transmitControl(kind: .inviteApproval, id: invitationID, payload: payload)
                self.inviteTransportStatus = sent
                    ? "Approval sent over BLE (attempt \(attempt))"
                    : "Approval waiting for a writable BLE link (attempt \(attempt))"
                try? await Task.sleep(for: .milliseconds(750))
            }
        }
    }

    @discardableResult
    private func transmitControl(kind: AuroraMeshPacketKind, id: UUID, payload: Data) -> Bool {
        let packet = AuroraMeshWirePacket(
            kind: kind,
            groupTag: Data(repeating: 0, count: 8),
            messageID: id,
            ttl: 1,
            payload: payload
        )
        guard let data = try? AuroraMeshWireCodec.encode(packet) else { return false }
        return link?.broadcast(data) == true
    }

    private func refreshSnapshot() async {
        guard let snapshot = await engine?.snapshot() else { return }
        groups = snapshot.groups
        messagesByGroup = snapshot.messagesByGroup
        reachableMemberIDs = snapshot.reachableMemberIDs
        displayNamesByGroup = snapshot.displayNamesByGroup
        for group in snapshot.groups {
            if let key = await engine?.keyMaterial(groupID: group.id, epoch: group.epoch) {
                try? vault.saveGroupKey(key, groupID: group.id, epoch: group.epoch)
                try? store?.recordKeyEpoch(groupID: group.id, epoch: group.epoch)
            }
        }
    }

    private func restoreHistoryAndRefresh() async {
        guard let engine else { return }
        let snapshot = await engine.snapshot()
        for group in snapshot.groups {
            _ = try? await engine.loadHistoryPage(groupID: group.id)
        }
        await refreshSnapshot()
    }

    private func message(for error: Error) -> String {
        switch error as? AuroraMeshError {
        case .messageTooLarge: "Messages are limited to 2,048 UTF-8 bytes."
        case .memberLimitReached: "This group already has 20 members."
        case .rateLimited: "Too many messages. Wait a moment and try again."
        case .invitationExpired: "That invite has expired. Ask for a new QR code."
        case .invitationAlreadyUsed: "That invite approval was already used."
        case .verificationFailed: "The invite verification failed."
        case .unauthorized: "This device is not a current member of that group."
        case .groupNotFound, .groupEnded: "That group is no longer available."
        case .cryptographyFailed: "Aurora cannot authenticate deletion because this group's protected key is unavailable."
        case .persistenceFailed: "Aurora could not securely save the group deletion. Please try again."
        default: "Mesh Chat could not complete that action."
        }
    }

    private static let defaultDisplayName = UIDevice.current.name

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func dataFromBase64URL(_ string: String) -> Data? {
        var value = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        return Data(base64Encoded: value)
    }
}
#endif
