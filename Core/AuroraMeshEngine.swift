#if AURORA_MESH_BETA
import CryptoKit
import Foundation

/// Radio-independent protocol state. Bluetooth, UI, and lifecycle policy live in the app target.
public actor AuroraMeshEngine {
    public typealias Clock = @Sendable () -> Date

    private struct PendingInvitation: Sendable {
        let invitation: AuroraMeshInvitation
        let ephemeralPrivateKey: Data
    }

    private var privateIdentity: AuroraMeshPrivateIdentity
    private let store: AuroraMeshStore
    private let now: Clock
    private var groups: [UUID: AuroraMeshGroup]
    private var groupKeys: [UUID: [Int: Data]]
    private var messages: [UUID: [AuroraMeshMessage]] = [:]
    private var senderSequences: [UUID: UInt64] = [:]
    private var recentIDs: [UUID] = []
    private var recentIDSet: Set<UUID> = []
    private var sendTimes: [String: [Date]] = [:]
    private var reachableAt: [String: Date] = [:]
    private var pendingAcknowledgements: [UUID: Set<UUID>] = [:]
    private var acknowledgementDeadlines: [UUID: Date] = [:]
    private var pendingInvitations: [UUID: PendingInvitation] = [:]
    private var displayNamesByGroup: [UUID: [String: String]] = [:]
    private var displayNameSequencesByGroup: [UUID: [String: UInt64]] = [:]

    public init(
        identity: AuroraMeshPrivateIdentity,
        store: AuroraMeshStore,
        groupKeys: [UUID: [Int: Data]] = [:],
        now: @escaping Clock = { Date() }
    ) throws {
        self.privateIdentity = identity
        self.store = store
        self.now = now
        self.groups = Dictionary(uniqueKeysWithValues: try store.groups().map { ($0.id, $0) })
        self.groupKeys = groupKeys
        for record in try store.displayNameRecords() {
            self.displayNamesByGroup[record.groupID, default: [:]][record.memberID] = record.displayName
            self.displayNameSequencesByGroup[record.groupID, default: [:]][record.memberID] = record.sequence
        }
        self.senderSequences = try Dictionary(uniqueKeysWithValues: self.groups.keys.map {
            ($0, try store.senderSequence(groupID: $0, senderID: identity.identity.id))
        })
    }

    public var identity: AuroraMeshIdentity { privateIdentity.identity }

    public func snapshot() -> AuroraMeshSnapshot {
        let cutoff = now().addingTimeInterval(-AuroraMeshLimits.presenceLifetime)
        reachableAt = reachableAt.filter { $0.value >= cutoff }
        return AuroraMeshSnapshot(
            groups: groups.values
                .filter { $0.endedAt == nil }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            messagesByGroup: messages,
            reachableMemberIDs: Set(reachableAt.keys),
            displayNamesByGroup: displayNamesByGroup
        )
    }

    public func setReachableMemberIDs(_ ids: Set<String>) {
        reachableAt = Dictionary(uniqueKeysWithValues: ids.map { ($0, now()) })
    }

    @discardableResult
    public func createGroup(name: String) throws -> AuroraMeshGroup {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              cleanName.lengthOfBytes(using: .utf8) <= AuroraMeshLimits.maximumGroupNameBytes
        else { throw AuroraMeshError.invalidName }
        let id = UUID()
        let grant = try AuroraMeshCrypto.makeGrant(
            groupID: id,
            epoch: 1,
            member: privateIdentity.identity,
            inviter: privateIdentity,
            issuedAt: now()
        )
        let group = AuroraMeshGroup(
            id: id,
            name: cleanName,
            creatorID: privateIdentity.identity.id,
            members: [grant]
        )
        groups[id] = group
        groupKeys[id] = [1: AuroraMeshCrypto.randomGroupKey()]
        try store.save(group: group)
        return group
    }

    public func keyMaterial(groupID: UUID, epoch: Int) -> Data? {
        groupKeys[groupID]?[epoch]
    }

    public func installKey(_ key: Data, groupID: UUID, epoch: Int) {
        groupKeys[groupID, default: [:]][epoch] = key
    }

    public func discardHistoricalKeys(groupID: UUID) -> [Int] {
        guard let currentEpoch = groups[groupID]?.epoch else { return [] }
        let removed = groupKeys[groupID, default: [:]].keys.filter { $0 != currentEpoch }
        for epoch in removed { groupKeys[groupID]?.removeValue(forKey: epoch) }
        return removed
    }

    public func updateIdentity(_ updatedIdentity: AuroraMeshPrivateIdentity) throws -> [AuroraMeshEngineEvent] {
        guard updatedIdentity.identity.id == privateIdentity.identity.id,
              updatedIdentity.identity.signingPublicKey == privateIdentity.identity.signingPublicKey,
              updatedIdentity.identity.agreementPublicKey == privateIdentity.identity.agreementPublicKey,
              let displayName = Self.validatedDisplayName(updatedIdentity.identity.displayName)
        else { throw AuroraMeshError.unauthorized }
        let previousIdentity = privateIdentity
        privateIdentity = updatedIdentity
        guard displayName != previousIdentity.identity.displayName else { return [] }

        do {
            var events: [AuroraMeshEngineEvent] = []
            for group in groups.values.sorted(by: { $0.id.uuidString < $1.id.uuidString })
                where group.endedAt == nil && isCurrentMember(updatedIdentity.identity.id, of: group) {
                let sequence = try nextSequence(groupID: group.id)
                let body = AuroraMeshPlainBody(
                    kind: .identityUpdate,
                    sender: updatedIdentity.identity,
                    senderSequence: sequence,
                    createdAt: now()
                )
                let packet = try makePacket(body: body, group: group)
                remember(packet.messageID)
                try store.recordSeenSequence(
                    groupID: group.id,
                    senderID: updatedIdentity.identity.id,
                    sequence: sequence
                )
                try store.recordSyncIndex(
                    groupID: group.id,
                    senderID: updatedIdentity.identity.id,
                    sequence: sequence
                )
                try store.recordDisplayName(
                    displayName,
                    groupID: group.id,
                    memberID: updatedIdentity.identity.id,
                    sequence: sequence
                )
                try store.save(packet: packet, groupID: group.id, firstSeenAt: now())
                displayNamesByGroup[group.id, default: [:]][updatedIdentity.identity.id] = displayName
                displayNameSequencesByGroup[group.id, default: [:]][updatedIdentity.identity.id] = sequence
                events.append(.transmit(packet))
            }
            return events
        } catch {
            privateIdentity = previousIdentity
            throw error
        }
    }

    public func sendText(_ text: String, groupID: UUID) throws -> [AuroraMeshEngineEvent] {
        guard let group = groups[groupID] else { throw AuroraMeshError.groupNotFound }
        guard group.endedAt == nil else { throw AuroraMeshError.groupEnded }
        guard isCurrentMember(privateIdentity.identity.id, of: group) else { throw AuroraMeshError.unauthorized }
        guard !text.isEmpty, text.lengthOfBytes(using: .utf8) <= AuroraMeshLimits.maximumTextBytes else {
            throw AuroraMeshError.messageTooLarge
        }
        try enforceRateLimit(for: privateIdentity.identity.id)
        let sequence = try nextSequence(groupID: groupID)
        let body = AuroraMeshPlainBody(
            kind: .text,
            sender: privateIdentity.identity,
            senderSequence: sequence,
            createdAt: now(),
            text: text,
            expectedRecipients: max(0, group.members.count - 1)
        )
        let packet = try makePacket(body: body, group: group)
        remember(packet.messageID)
        try store.recordSeenSequence(groupID: groupID, senderID: privateIdentity.identity.id, sequence: sequence)
        try store.recordSyncIndex(groupID: groupID, senderID: privateIdentity.identity.id, sequence: sequence)
        let message = message(from: body, groupID: groupID, firstSeenAt: now())
        messages[groupID, default: []].append(message)
        try store.save(packet: packet, groupID: groupID, firstSeenAt: message.firstSeenAt)
        return [.transmit(packet), .receivedMessage(groupID: groupID, messageID: packet.messageID)]
    }

    public func ingest(_ packet: AuroraMeshWirePacket) throws -> [AuroraMeshEngineEvent] {
        guard packet.kind == .groupEnvelope, packet.ttl > 0 else { throw AuroraMeshError.invalidPacket }
        guard !recentIDSet.contains(packet.messageID), !store.isTombstoned(messageID: packet.messageID) else {
            throw AuroraMeshError.duplicateMessage
        }
        guard let (group, key) = matchingCurrentGroup(for: packet.groupTag) else {
            throw AuroraMeshError.unauthorized
        }
        let signed = try AuroraMeshCrypto.open(
            packet.payload,
            groupID: group.id,
            epoch: group.epoch,
            groupKey: key
        )
        let body = signed.body
        guard body.messageID == packet.messageID,
              isCurrentMember(body.sender.id, of: group),
              group.members.contains(where: {
                  $0.member.id == body.sender.id && $0.member.signingPublicKey == body.sender.signingPublicKey
              })
        else { throw AuroraMeshError.unauthorized }
        guard now().timeIntervalSince(body.createdAt) <= AuroraMeshLimits.catchUpInterval else {
            throw AuroraMeshError.expiredMessage
        }
        guard let displayName = Self.validatedDisplayName(body.sender.displayName) else {
            throw AuroraMeshError.invalidName
        }
        try validateAndRecordSequence(body.senderSequence, senderID: body.sender.id, groupID: group.id)
        if body.kind == .text { try enforceRateLimit(for: body.sender.id) }
        reachableAt[body.sender.id] = now()
        remember(packet.messageID)
        try store.save(packet: packet, groupID: group.id, firstSeenAt: now())
        if body.senderSequence > displayNameSequencesByGroup[group.id, default: [:]][body.sender.id, default: 0] {
            try store.recordDisplayName(
                displayName,
                groupID: group.id,
                memberID: body.sender.id,
                sequence: body.senderSequence
            )
            displayNamesByGroup[group.id, default: [:]][body.sender.id] = displayName
            displayNameSequencesByGroup[group.id, default: [:]][body.sender.id] = body.senderSequence
        }

        var events: [AuroraMeshEngineEvent] = []
        switch body.kind {
        case .text:
            let incoming = message(from: body, groupID: group.id, firstSeenAt: now())
            messages[group.id, default: []].append(incoming)
            events.append(.receivedMessage(groupID: group.id, messageID: body.messageID))
            pendingAcknowledgements[group.id, default: []].insert(body.messageID)
            if acknowledgementDeadlines[group.id] == nil {
                acknowledgementDeadlines[group.id] = now().addingTimeInterval(AuroraMeshLimits.acknowledgementDelay)
            }
            events.append(.acknowledgementPending(groupID: group.id))
        case .acknowledgement:
            for messageID in body.acknowledgedMessageIDs {
                guard let index = messages[group.id]?.firstIndex(where: { $0.id == messageID }) else { continue }
                messages[group.id]?[index].acknowledgedMemberIDs.insert(body.sender.id)
                try store.recordAcknowledgement(messageID: messageID, memberID: body.sender.id)
                events.append(.deliveryChanged(groupID: group.id, messageID: messageID))
            }
        case .identityUpdate:
            break
        case .memberGrant:
            guard let grant = body.memberGrant,
                  grant.groupID == group.id,
                  grant.epoch == group.epoch,
                  grant.inviterID == body.sender.id,
                  AuroraMeshCrypto.verifyGrant(grant, inviter: body.sender),
                  !group.members.contains(where: { $0.member.id == grant.member.id }),
                  group.members.count < AuroraMeshLimits.maximumMembers
            else { throw AuroraMeshError.verificationFailed }
            var updated = group
            updated.members.append(grant)
            groups[group.id] = updated
            try store.save(group: updated)
        case .rekey:
            guard body.sender.id == group.creatorID,
                  let payloadData = body.payload,
                  let rekey = try? Self.decoder.decode(AuroraMeshRekeyPayload.self, from: payloadData),
                  rekey.group.id == group.id,
                  rekey.group.creatorID == group.creatorID,
                  rekey.group.epoch == group.epoch + 1,
                  rekey.group.members.count <= AuroraMeshLimits.maximumMembers,
                  rekey.group.members.allSatisfy({ grant in
                      grant.groupID == group.id && grant.epoch == rekey.group.epoch
                          && grant.inviterID == group.creatorID
                          && AuroraMeshCrypto.verifyGrant(grant, inviter: body.sender)
                  }),
                  rekey.group.members.contains(where: { $0.member.id == privateIdentity.identity.id }),
                  let package = rekey.packages.first(where: { $0.recipientID == privateIdentity.identity.id })
            else { throw AuroraMeshError.unauthorized }
            let newKey = try AuroraMeshCrypto.openGroupKey(
                package.ciphertext,
                recipientAgreementPrivateKey: privateIdentity.agreementPrivateKey,
                senderAgreementPublicKey: body.sender.agreementPublicKey,
                groupID: group.id,
                epoch: rekey.group.epoch
            )
            groups[group.id] = rekey.group
            groupKeys[group.id, default: [:]][rekey.group.epoch] = newKey
            try store.save(group: rekey.group)
        case .leave:
            var updated = group
            updated.members.removeAll { $0.member.id == body.sender.id }
            groups[group.id] = updated
            try store.save(group: updated)
        case .endGroup:
            guard body.sender.id == group.creatorID else { throw AuroraMeshError.unauthorized }
            var updated = group
            updated.endedAt = body.createdAt
            try finishGroupEnd(updated, packet: packet, firstSeenAt: now())
        case .syncSummary:
            guard let payload = body.payload,
                  let summary = try? Self.decoder.decode(AuroraMeshSyncSummary.self, from: payload),
                  summary.requesterID == body.sender.id
            else { throw AuroraMeshError.invalidPacket }
            events.append(contentsOf: try catchUpEvents(for: body.sender.id, group: group))
        }
        if packet.ttl > 1 {
            var relayed = packet
            relayed.ttl -= 1
            events.append(.transmit(relayed))
        }
        return events
    }

    public func markRelayed(messageID: UUID, groupID: UUID) {
        guard let index = messages[groupID]?.firstIndex(where: { $0.id == messageID }) else { return }
        messages[groupID]?[index].wasRelayed = true
    }

    public func catchUpPackets(groupID: UUID) throws -> [AuroraMeshWirePacket] {
        guard groups[groupID] != nil else { throw AuroraMeshError.groupNotFound }
        return try store.envelopes(
            groupID: groupID,
            since: now().addingTimeInterval(-AuroraMeshLimits.catchUpInterval)
        ).map(\.packet)
    }

    public func makeSyncSummaryPackets() throws -> [AuroraMeshWirePacket] {
        var packets: [AuroraMeshWirePacket] = []
        for group in groups.values where group.endedAt == nil && isCurrentMember(privateIdentity.identity.id, of: group) {
            var indexes = try store.syncIndexes(groupID: group.id)
            indexes[privateIdentity.identity.id] = senderSequences[group.id, default: 0]
            let sequence = try nextSequence(groupID: group.id)
            let summary = AuroraMeshSyncSummary(
                requesterID: privateIdentity.identity.id,
                highestSequences: indexes
            )
            let body = AuroraMeshPlainBody(
                kind: .syncSummary,
                sender: privateIdentity.identity,
                senderSequence: sequence,
                createdAt: now(),
                payload: try Self.encoder.encode(summary)
            )
            let packet = try makePacket(body: body, group: group, ttl: 1)
            remember(packet.messageID)
            try store.recordSeenSequence(
                groupID: group.id,
                senderID: privateIdentity.identity.id,
                sequence: sequence
            )
            try store.recordSyncIndex(
                groupID: group.id,
                senderID: privateIdentity.identity.id,
                sequence: sequence
            )
            packets.append(packet)
        }
        return packets
    }

    public func flushAcknowledgements(groupID: UUID) throws -> [AuroraMeshEngineEvent] {
        guard let group = groups[groupID], group.endedAt == nil else { return [] }
        let ids = Array(pendingAcknowledgements.removeValue(forKey: groupID) ?? []).sorted {
            $0.uuidString < $1.uuidString
        }
        acknowledgementDeadlines.removeValue(forKey: groupID)
        guard !ids.isEmpty else { return [] }
        return [.transmit(try acknowledgement(for: ids, group: group))]
    }

    public func flushDueAcknowledgements() throws -> [AuroraMeshEngineEvent] {
        let due = acknowledgementDeadlines.filter { $0.value <= now() }.map(\.key)
        return try due.flatMap { try flushAcknowledgements(groupID: $0) }
    }

    public func deleteLocalHistory(groupID: UUID) throws {
        guard groups[groupID] != nil else { throw AuroraMeshError.groupNotFound }
        try store.deleteHistory(groupID: groupID, at: now())
        messages[groupID] = []
    }

    @discardableResult
    public func loadHistoryPage(groupID: UUID, before: Date? = nil) throws -> Int {
        guard groups[groupID] != nil, let keys = groupKeys[groupID], !keys.isEmpty else {
            throw AuroraMeshError.groupNotFound
        }
        var loaded = 0
        for stored in try store.historyPage(groupID: groupID, before: before) {
            guard !messages[groupID, default: []].contains(where: { $0.id == stored.packet.messageID }),
                  let match = keys.first(where: {
                      AuroraMeshCrypto.groupTag(groupKey: $0.value, epoch: $0.key) == stored.packet.groupTag
                  }),
                  let signed = try? AuroraMeshCrypto.open(
                    stored.packet.payload, groupID: groupID, epoch: match.key, groupKey: match.value
                  ),
                  signed.body.kind == .text
            else { continue }
            var restored = message(
                from: signed.body,
                groupID: groupID,
                epoch: match.key,
                firstSeenAt: stored.firstSeenAt
            )
            restored.acknowledgedMemberIDs = try store.acknowledgementMemberIDs(messageID: restored.id)
            messages[groupID, default: []].append(restored)
            loaded += 1
        }
        messages[groupID]?.sort { $0.createdAt < $1.createdAt }
        return loaded
    }

    public func makeInvitation(groupID: UUID) throws -> AuroraMeshInvitation {
        guard let group = groups[groupID], group.endedAt == nil else { throw AuroraMeshError.groupNotFound }
        guard isCurrentMember(privateIdentity.identity.id, of: group) else { throw AuroraMeshError.unauthorized }
        guard group.members.count < AuroraMeshLimits.maximumMembers else { throw AuroraMeshError.memberLimitReached }
        let ephemeralPrivateKey = AuroraMeshCrypto.ephemeralPrivateKey()
        let invitation = AuroraMeshInvitation(
            version: AuroraMeshLimits.protocolVersion,
            invitationID: UUID(),
            groupID: group.id,
            groupName: group.name,
            epoch: group.epoch,
            inviter: privateIdentity.identity,
            ephemeralPublicKey: try AuroraMeshCrypto.ephemeralPublicKey(privateKey: ephemeralPrivateKey),
            expiresAt: now().addingTimeInterval(AuroraMeshLimits.invitationLifetime)
        )
        pendingInvitations[invitation.invitationID] = PendingInvitation(
            invitation: invitation,
            ephemeralPrivateKey: ephemeralPrivateKey
        )
        return invitation
    }

    public func makeJoinContext(for invitation: AuroraMeshInvitation) throws -> AuroraMeshJoinContext {
        guard invitation.version == AuroraMeshLimits.protocolVersion else { throw AuroraMeshError.unsupportedVersion }
        guard invitation.expiresAt > now() else { throw AuroraMeshError.invitationExpired }
        let privateKey = AuroraMeshCrypto.ephemeralPrivateKey()
        let publicKey = try AuroraMeshCrypto.ephemeralPublicKey(privateKey: privateKey)
        let request = AuroraMeshJoinRequest(
            invitationID: invitation.invitationID,
            joiner: privateIdentity.identity,
            ephemeralPublicKey: publicKey
        )
        let key = try AuroraMeshCrypto.invitationSessionKey(
            ownPrivateKey: privateKey,
            remotePublicKey: invitation.ephemeralPublicKey,
            invitationID: invitation.invitationID
        )
        let code = AuroraMeshCrypto.verificationCode(
            key: key,
            invitationID: invitation.invitationID,
            inviterEphemeralKey: invitation.ephemeralPublicKey,
            joinerEphemeralKey: publicKey
        )
        return AuroraMeshJoinContext(request: request, ephemeralPrivateKey: privateKey, verificationCode: code)
    }

    public func verificationCode(for request: AuroraMeshJoinRequest) throws -> String {
        guard let pending = pendingInvitations[request.invitationID] else { throw AuroraMeshError.invitationNotFound }
        guard pending.invitation.expiresAt > now() else { throw AuroraMeshError.invitationExpired }
        let key = try AuroraMeshCrypto.invitationSessionKey(
            ownPrivateKey: pending.ephemeralPrivateKey,
            remotePublicKey: request.ephemeralPublicKey,
            invitationID: request.invitationID
        )
        return AuroraMeshCrypto.verificationCode(
            key: key,
            invitationID: request.invitationID,
            inviterEphemeralKey: pending.invitation.ephemeralPublicKey,
            joinerEphemeralKey: request.ephemeralPublicKey
        )
    }

    public func approve(_ request: AuroraMeshJoinRequest) throws -> AuroraMeshApprovalResult {
        guard let pending = pendingInvitations.removeValue(forKey: request.invitationID) else {
            throw AuroraMeshError.invitationNotFound
        }
        guard pending.invitation.expiresAt > now() else { throw AuroraMeshError.invitationExpired }
        guard var group = groups[pending.invitation.groupID],
              let groupKey = groupKeys[group.id]?[group.epoch]
        else { throw AuroraMeshError.groupNotFound }
        guard group.members.count < AuroraMeshLimits.maximumMembers else { throw AuroraMeshError.memberLimitReached }
        let grant = try AuroraMeshCrypto.makeGrant(
            groupID: group.id,
            epoch: group.epoch,
            member: request.joiner,
            inviter: privateIdentity,
            issuedAt: now()
        )
        group.members.append(grant)
        groups[group.id] = group
        try store.save(group: group)
        let sessionKey = try AuroraMeshCrypto.invitationSessionKey(
            ownPrivateKey: pending.ephemeralPrivateKey,
            remotePublicKey: request.ephemeralPublicKey,
            invitationID: request.invitationID
        )
        let ciphertext = try AuroraMeshCrypto.sealApproval(
            AuroraMeshApprovalPayload(group: group, groupKey: groupKey, grant: grant),
            key: sessionKey
        )
        let approval = AuroraMeshInviteApproval(invitationID: request.invitationID, ciphertext: ciphertext)
        let sequence = try nextSequence(groupID: group.id)
        let grantBody = AuroraMeshPlainBody(
            kind: .memberGrant,
            sender: privateIdentity.identity,
            senderSequence: sequence,
            createdAt: now(),
            memberGrant: grant
        )
        let grantPacket = try makePacket(body: grantBody, group: group)
        remember(grantPacket.messageID)
        try store.save(packet: grantPacket, groupID: group.id, firstSeenAt: now())
        return AuroraMeshApprovalResult(approval: approval, events: [.transmit(grantPacket)])
    }

    public func removeMember(memberID: String, groupID: UUID) throws -> [AuroraMeshEngineEvent] {
        guard let oldGroup = groups[groupID], oldGroup.endedAt == nil else { throw AuroraMeshError.groupNotFound }
        guard oldGroup.creatorID == privateIdentity.identity.id else { throw AuroraMeshError.unauthorized }
        guard memberID != oldGroup.creatorID,
              oldGroup.members.contains(where: { $0.member.id == memberID })
        else { throw AuroraMeshError.unauthorized }
        let retained = oldGroup.members.map(\.member).filter { $0.id != memberID }
        let newEpoch = oldGroup.epoch + 1
        let grants = try retained.map {
            try AuroraMeshCrypto.makeGrant(
                groupID: groupID,
                epoch: newEpoch,
                member: $0,
                inviter: privateIdentity,
                issuedAt: now()
            )
        }
        let updated = AuroraMeshGroup(
            id: groupID,
            name: oldGroup.name,
            creatorID: oldGroup.creatorID,
            epoch: newEpoch,
            members: grants
        )
        let newKey = AuroraMeshCrypto.randomGroupKey()
        let packages = try retained.map { member in
            AuroraMeshRekeyPackage(
                recipientID: member.id,
                ciphertext: try AuroraMeshCrypto.sealGroupKey(
                    newKey,
                    senderAgreementPrivateKey: privateIdentity.agreementPrivateKey,
                    recipientAgreementPublicKey: member.agreementPublicKey,
                    groupID: groupID,
                    epoch: newEpoch
                )
            )
        }
        let sequence = try nextSequence(groupID: groupID)
        let body = AuroraMeshPlainBody(
            kind: .rekey,
            sender: privateIdentity.identity,
            senderSequence: sequence,
            createdAt: now(),
            payload: try Self.encoder.encode(AuroraMeshRekeyPayload(group: updated, packages: packages))
        )
        let packet = try makePacket(body: body, group: oldGroup)
        remember(packet.messageID)
        try store.save(packet: packet, groupID: groupID, firstSeenAt: now())
        groups[groupID] = updated
        groupKeys[groupID, default: [:]][newEpoch] = newKey
        try store.save(group: updated)
        return [.transmit(packet)]
    }

    public func leaveGroup(groupID: UUID) throws -> [AuroraMeshEngineEvent] {
        guard var group = groups[groupID], group.endedAt == nil else { throw AuroraMeshError.groupNotFound }
        guard group.creatorID != privateIdentity.identity.id else { throw AuroraMeshError.unauthorized }
        let sequence = try nextSequence(groupID: groupID)
        let packet = try makePacket(
            body: AuroraMeshPlainBody(
                kind: .leave,
                sender: privateIdentity.identity,
                senderSequence: sequence,
                createdAt: now()
            ),
            group: group
        )
        remember(packet.messageID)
        try store.save(packet: packet, groupID: groupID, firstSeenAt: now())
        group.members.removeAll { $0.member.id == privateIdentity.identity.id }
        groups[groupID] = group
        try store.save(group: group)
        return [.transmit(packet)]
    }

    public func endGroup(groupID: UUID) throws -> [AuroraMeshEngineEvent] {
        guard var group = groups[groupID], group.endedAt == nil else { throw AuroraMeshError.groupNotFound }
        guard group.creatorID == privateIdentity.identity.id else { throw AuroraMeshError.unauthorized }
        let sequence = try nextSequence(groupID: groupID)
        let date = now()
        let packet = try makePacket(
            body: AuroraMeshPlainBody(
                kind: .endGroup,
                sender: privateIdentity.identity,
                senderSequence: sequence,
                createdAt: date
            ),
            group: group
        )
        remember(packet.messageID)
        group.endedAt = date
        try finishGroupEnd(group, packet: packet, firstSeenAt: date)
        return [.transmit(packet)]
    }

    public func pendingTerminationPackets() throws -> [AuroraMeshWirePacket] {
        let cutoff = now().addingTimeInterval(-AuroraMeshLimits.catchUpInterval)
        return try groups.values
            .filter { group in
                guard let endedAt = group.endedAt else { return false }
                return endedAt > cutoff
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .compactMap { group in
                guard var packet = try store.terminationPacket(groupID: group.id) else { return nil }
                packet.ttl = AuroraMeshLimits.maximumHops
                return packet
            }
    }

    public func pendingGroupCleanups() throws -> [AuroraMeshGroupCleanup] {
        let cutoff = now().addingTimeInterval(-AuroraMeshLimits.catchUpInterval)
        return try groups.values.compactMap { group -> AuroraMeshGroupCleanup? in
            guard let endedAt = group.endedAt else { return nil }
            var knownEpochs = Set(try store.keyEpochs(groupID: group.id))
            if let keys = groupKeys[group.id]?.keys {
                knownEpochs.formUnion(keys)
            }
            knownEpochs.insert(group.epoch)
            let removesGroup = endedAt <= cutoff
            let epochs = knownEpochs
                .filter { removesGroup || $0 != group.epoch }
                .sorted()
            guard removesGroup || !epochs.isEmpty else { return nil }
            return AuroraMeshGroupCleanup(groupID: group.id, epochs: epochs, removesGroup: removesGroup)
        }.sorted { $0.groupID.uuidString < $1.groupID.uuidString }
    }

    public func completeGroupCleanup(_ cleanup: AuroraMeshGroupCleanup) throws {
        guard let group = groups[cleanup.groupID], group.endedAt != nil else {
            throw AuroraMeshError.groupNotFound
        }
        if cleanup.removesGroup {
            let cutoff = now().addingTimeInterval(-AuroraMeshLimits.catchUpInterval)
            guard let endedAt = group.endedAt, endedAt <= cutoff else {
                throw AuroraMeshError.unauthorized
            }
            try store.purgeGroup(groupID: group.id)
            groups.removeValue(forKey: group.id)
            groupKeys.removeValue(forKey: group.id)
            messages.removeValue(forKey: group.id)
            senderSequences.removeValue(forKey: group.id)
            pendingAcknowledgements.removeValue(forKey: group.id)
            acknowledgementDeadlines.removeValue(forKey: group.id)
            displayNamesByGroup.removeValue(forKey: group.id)
            displayNameSequencesByGroup.removeValue(forKey: group.id)
        } else {
            guard cleanup.epochs.allSatisfy({ $0 != group.epoch }) else {
                throw AuroraMeshError.unauthorized
            }
            for epoch in cleanup.epochs {
                groupKeys[group.id]?.removeValue(forKey: epoch)
                try store.deleteKeyEpoch(groupID: group.id, epoch: epoch)
            }
        }
    }

    @discardableResult
    public func consume(
        _ approval: AuroraMeshInviteApproval,
        invitation: AuroraMeshInvitation,
        context: AuroraMeshJoinContext
    ) throws -> AuroraMeshGroup {
        guard approval.invitationID == invitation.invitationID,
              context.request.invitationID == invitation.invitationID,
              invitation.expiresAt > now()
        else { throw AuroraMeshError.invitationExpired }
        guard !store.isInvitationConsumed(approval.invitationID) else {
            throw AuroraMeshError.invitationAlreadyUsed
        }
        let key = try AuroraMeshCrypto.invitationSessionKey(
            ownPrivateKey: context.ephemeralPrivateKey,
            remotePublicKey: invitation.ephemeralPublicKey,
            invitationID: invitation.invitationID
        )
        let payload = try AuroraMeshCrypto.openApproval(approval.ciphertext, key: key)
        guard payload.group.id == invitation.groupID,
              payload.group.epoch == invitation.epoch,
              payload.grant.member.id == privateIdentity.identity.id,
              payload.group.members.contains(payload.grant),
              let inviter = payload.group.members.first(where: { $0.member.id == payload.grant.inviterID })?.member,
              AuroraMeshCrypto.verifyGrant(payload.grant, inviter: inviter)
        else { throw AuroraMeshError.verificationFailed }
        groups[payload.group.id] = payload.group
        groupKeys[payload.group.id, default: [:]][payload.group.epoch] = payload.groupKey
        try store.save(group: payload.group)
        try store.markInvitationConsumed(approval.invitationID, at: now())
        return payload.group
    }

    private func makePacket(
        body: AuroraMeshPlainBody,
        group: AuroraMeshGroup,
        ttl: UInt8 = AuroraMeshLimits.maximumHops
    ) throws -> AuroraMeshWirePacket {
        guard let key = groupKeys[group.id]?[group.epoch] else { throw AuroraMeshError.cryptographyFailed }
        let signed = try AuroraMeshCrypto.sign(body, privateKey: privateIdentity.signingPrivateKey)
        return AuroraMeshWirePacket(
            kind: .groupEnvelope,
            groupTag: AuroraMeshCrypto.groupTag(groupKey: key, epoch: group.epoch),
            messageID: body.messageID,
            ttl: ttl,
            payload: try AuroraMeshCrypto.seal(signed, groupID: group.id, epoch: group.epoch, groupKey: key)
        )
    }

    private func finishGroupEnd(
        _ group: AuroraMeshGroup,
        packet: AuroraMeshWirePacket,
        firstSeenAt: Date
    ) throws {
        try store.markGroupEnded(group, terminationPacket: packet, firstSeenAt: firstSeenAt)
        groups[group.id] = group
        messages.removeValue(forKey: group.id)
        senderSequences.removeValue(forKey: group.id)
        pendingAcknowledgements.removeValue(forKey: group.id)
        acknowledgementDeadlines.removeValue(forKey: group.id)
        displayNamesByGroup.removeValue(forKey: group.id)
        displayNameSequencesByGroup.removeValue(forKey: group.id)
    }

    private func acknowledgement(for messageIDs: [UUID], group: AuroraMeshGroup) throws -> AuroraMeshWirePacket {
        let sequence = try nextSequence(groupID: group.id)
        return try makePacket(
            body: AuroraMeshPlainBody(
                kind: .acknowledgement,
                sender: privateIdentity.identity,
                senderSequence: sequence,
                createdAt: now(),
                acknowledgedMessageIDs: messageIDs
            ),
            group: group
        )
    }

    private func matchingCurrentGroup(for tag: Data) -> (AuroraMeshGroup, Data)? {
        for group in groups.values where group.endedAt == nil {
            guard let key = groupKeys[group.id]?[group.epoch] else { continue }
            if AuroraMeshCrypto.groupTag(groupKey: key, epoch: group.epoch) == tag { return (group, key) }
        }
        return nil
    }

    private func isCurrentMember(_ id: String, of group: AuroraMeshGroup) -> Bool {
        group.members.contains { $0.epoch == group.epoch && $0.member.id == id }
    }

    private func message(
        from body: AuroraMeshPlainBody,
        groupID: UUID,
        epoch: Int? = nil,
        firstSeenAt: Date
    ) -> AuroraMeshMessage {
        AuroraMeshMessage(
            id: body.messageID,
            groupID: groupID,
            epoch: epoch ?? groups[groupID]?.epoch ?? 0,
            senderID: body.sender.id,
            senderSequence: body.senderSequence,
            createdAt: body.createdAt,
            firstSeenAt: firstSeenAt,
            text: body.text ?? "",
            expectedRecipients: body.expectedRecipients
        )
    }

    private func remember(_ id: UUID) {
        recentIDs.append(id)
        recentIDSet.insert(id)
        if recentIDs.count > AuroraMeshLimits.maximumRecentMessageIDs {
            recentIDSet.remove(recentIDs.removeFirst())
        }
    }

    private func enforceRateLimit(for senderID: String) throws {
        let cutoff = now().addingTimeInterval(-60)
        var timestamps = sendTimes[senderID, default: []].filter { $0 >= cutoff }
        guard timestamps.count < AuroraMeshLimits.maximumMessagesPerMinute else {
            throw AuroraMeshError.rateLimited
        }
        timestamps.append(now())
        sendTimes[senderID] = timestamps
    }

    private func validateAndRecordSequence(
        _ sequence: UInt64,
        senderID: String,
        groupID: UUID
    ) throws {
        let highest = try store.syncIndex(groupID: groupID, senderID: senderID)
        guard try !store.hasSeenSequence(groupID: groupID, senderID: senderID, sequence: sequence) else {
            throw AuroraMeshError.sequenceReplay
        }
        if highest > AuroraMeshLimits.maximumSequenceReorderWindow,
           sequence <= highest - AuroraMeshLimits.maximumSequenceReorderWindow {
            throw AuroraMeshError.sequenceReplay
        }
        try store.recordSeenSequence(groupID: groupID, senderID: senderID, sequence: sequence)
        try store.recordSyncIndex(groupID: groupID, senderID: senderID, sequence: sequence)
    }

    private func catchUpEvents(
        for requesterID: String,
        group: AuroraMeshGroup
    ) throws -> [AuroraMeshEngineEvent] {
        guard let requesterGrant = group.members.first(where: { $0.member.id == requesterID }),
              let key = groupKeys[group.id]?[group.epoch]
        else { throw AuroraMeshError.unauthorized }
        let earliest = max(
            requesterGrant.issuedAt,
            now().addingTimeInterval(-AuroraMeshLimits.catchUpInterval)
        )
        let currentTag = AuroraMeshCrypto.groupTag(groupKey: key, epoch: group.epoch)
        var packets: [AuroraMeshWirePacket] = []
        for stored in try store.envelopes(groupID: group.id, since: earliest) {
            guard stored.packet.groupTag == currentTag,
                  let signed = try? AuroraMeshCrypto.open(
                    stored.packet.payload,
                    groupID: group.id,
                    epoch: group.epoch,
                    groupKey: key
                  ),
                  (signed.body.kind == .text || signed.body.kind == .identityUpdate),
                  signed.body.createdAt >= requesterGrant.issuedAt
            else { continue }
            var packet = stored.packet
            packet.ttl = AuroraMeshLimits.maximumHops
            packets.append(packet)
            if packets.count == AuroraMeshLimits.maximumCatchUpMessages { break }
        }
        return packets.map(AuroraMeshEngineEvent.transmit)
    }

    private func nextSequence(groupID: UUID) throws -> UInt64 {
        let value = senderSequences[groupID, default: 0] + 1
        senderSequences[groupID] = value
        try store.saveSenderSequence(value, groupID: groupID, senderID: privateIdentity.identity.id)
        return value
    }

    private static func validatedDisplayName(_ displayName: String) -> String? {
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              cleanName.lengthOfBytes(using: .utf8) <= AuroraMeshLimits.maximumDisplayNameBytes
        else { return nil }
        return cleanName
    }

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
}
#endif
