#if AURORA_MESH_BETA
import XCTest
#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class AuroraMeshTests: XCTestCase {
    func testWireCodecRoundTripAndMalformedFrames() throws {
        let packet = AuroraMeshWirePacket(
            kind: .groupEnvelope,
            groupTag: Data(repeating: 7, count: 8),
            messageID: UUID(),
            ttl: 7,
            payload: Data("ciphertext".utf8)
        )
        XCTAssertEqual(try AuroraMeshWireCodec.decode(AuroraMeshWireCodec.encode(packet)), packet)
        XCTAssertThrowsError(try AuroraMeshWireCodec.decode(Data([0x41, 0x4D])))
        var corrupted = try AuroraMeshWireCodec.encode(packet)
        corrupted[4] = 99
        XCTAssertThrowsError(try AuroraMeshWireCodec.decode(corrupted))
        corrupted = try AuroraMeshWireCodec.encode(packet)
        corrupted[32] &+= 1
        XCTAssertThrowsError(try AuroraMeshWireCodec.decode(corrupted))
    }

    func testEncryptionSignatureTamperingAndWrongEpochFailClosed() throws {
        let identity = try AuroraMeshCrypto.makeIdentity(displayName: "Alice")
        let groupID = UUID()
        let key = AuroraMeshCrypto.randomGroupKey()
        let body = AuroraMeshPlainBody(
            kind: .text,
            sender: identity.identity,
            senderSequence: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            text: "hello"
        )
        let signed = try AuroraMeshCrypto.sign(body, privateKey: identity.signingPrivateKey)
        XCTAssertTrue(AuroraMeshCrypto.verify(signed))
        let sealed = try AuroraMeshCrypto.seal(signed, groupID: groupID, epoch: 1, groupKey: key)
        XCTAssertEqual(try AuroraMeshCrypto.open(sealed, groupID: groupID, epoch: 1, groupKey: key), signed)
        var tampered = sealed
        tampered[tampered.count / 2] ^= 1
        XCTAssertThrowsError(try AuroraMeshCrypto.open(tampered, groupID: groupID, epoch: 1, groupKey: key))
        XCTAssertThrowsError(try AuroraMeshCrypto.open(sealed, groupID: groupID, epoch: 2, groupKey: key))
    }

    func testInviteCodesApprovalAndNoGroupKeyInInvitation() async throws {
        let alice = try AuroraMeshCrypto.makeIdentity(displayName: "Alice")
        let bob = try AuroraMeshCrypto.makeIdentity(displayName: "Bob")
        let aliceEngine = try makeEngine(identity: alice)
        let bobEngine = try makeEngine(identity: bob)
        let group = try await aliceEngine.createGroup(name: "Trail Team")
        let invitation = try await aliceEngine.makeInvitation(groupID: group.id)
        let encodedInvitation = try JSONEncoder().encode(invitation)
        let aliceGroupKey = await aliceEngine.keyMaterial(groupID: group.id, epoch: 1)
        let groupKey = try XCTUnwrap(aliceGroupKey)
        XCTAssertFalse(encodedInvitation.contains(groupKey))

        let context = try await bobEngine.makeJoinContext(for: invitation)
        let inviterCode = try await aliceEngine.verificationCode(for: context.request)
        XCTAssertEqual(inviterCode, context.verificationCode)
        XCTAssertEqual(context.verificationCode.count, 6)
        let result = try await aliceEngine.approve(context.request)
        let imported = try await bobEngine.consume(result.approval, invitation: invitation, context: context)
        XCTAssertEqual(imported.members.count, 2)
        let bobGroupKey = await bobEngine.keyMaterial(groupID: group.id, epoch: 1)
        XCTAssertEqual(bobGroupKey, groupKey)
        await XCTAssertThrowsErrorAsync(
            try await bobEngine.consume(result.approval, invitation: invitation, context: context)
        ) { error in
            XCTAssertEqual(error as? AuroraMeshError, .invitationAlreadyUsed)
        }
    }

    func testInviteExpiresAtFiveMinutes() async throws {
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000))
        let aliceEngine = try makeEngine(
            identity: AuroraMeshCrypto.makeIdentity(displayName: "Alice"),
            now: { clock.value }
        )
        let bobEngine = try makeEngine(
            identity: AuroraMeshCrypto.makeIdentity(displayName: "Bob"),
            now: { clock.value }
        )
        let group = try await aliceEngine.createGroup(name: "Team")
        let invite = try await aliceEngine.makeInvitation(groupID: group.id)
        clock.value = invite.expiresAt.addingTimeInterval(0.001)
        await XCTAssertThrowsErrorAsync(try await bobEngine.makeJoinContext(for: invite)) { error in
            XCTAssertEqual(error as? AuroraMeshError, .invitationExpired)
        }
    }

    func testMessageAcknowledgementReplayAndTombstone() async throws {
        let pair = try await makeJoinedPair()
        let sendEvents = try await pair.alice.sendText("Need water", groupID: pair.group.id)
        let packet = try XCTUnwrap(transmissions(in: sendEvents).first)
        let bobEvents = try await pair.bob.ingest(packet)
        await XCTAssertThrowsErrorAsync(try await pair.bob.ingest(packet)) { error in
            XCTAssertEqual(error as? AuroraMeshError, .duplicateMessage)
        }
        XCTAssertTrue(bobEvents.contains(.acknowledgementPending(groupID: pair.group.id)))
        let acknowledgementEvents = try await pair.bob.flushAcknowledgements(groupID: pair.group.id)
        let acknowledgement = try XCTUnwrap(transmissions(in: acknowledgementEvents).first)
        _ = try await pair.alice.ingest(acknowledgement)
        let aliceSnapshot = await pair.alice.snapshot()
        let sent = try XCTUnwrap(aliceSnapshot.messagesByGroup[pair.group.id]?.first)
        XCTAssertEqual(sent.deliveryState, .delivered(received: 1, expected: 1))

        try await pair.bob.deleteLocalHistory(groupID: pair.group.id)
        await XCTAssertThrowsErrorAsync(try await pair.bob.ingest(packet)) { error in
            XCTAssertEqual(error as? AuroraMeshError, .duplicateMessage)
        }
    }

    func testAcknowledgementsAreBatched() async throws {
        let pair = try await makeJoinedPair()
        let firstEvents = try await pair.alice.sendText("one", groupID: pair.group.id)
        let secondEvents = try await pair.alice.sendText("two", groupID: pair.group.id)
        let first = try XCTUnwrap(transmissions(in: firstEvents).first)
        let second = try XCTUnwrap(transmissions(in: secondEvents).first)
        _ = try await pair.bob.ingest(first)
        _ = try await pair.bob.ingest(second)
        let batch = try await pair.bob.flushAcknowledgements(groupID: pair.group.id)
        XCTAssertEqual(transmissions(in: batch).count, 1)
        _ = try await pair.alice.ingest(try XCTUnwrap(transmissions(in: batch).first))
        let messages = await pair.alice.snapshot().messagesByGroup[pair.group.id] ?? []
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages.allSatisfy { $0.deliveryState == .delivered(received: 1, expected: 1) })
    }

    func testSequenceReplayWithDifferentPacketIDIsRejected() async throws {
        let pair = try await makeJoinedPair()
        let originalEvents = try await pair.alice.sendText("original", groupID: pair.group.id)
        let original = try XCTUnwrap(transmissions(in: originalEvents).first)
        _ = try await pair.bob.ingest(original)
        let keyMaterial = await pair.alice.keyMaterial(groupID: pair.group.id, epoch: 1)
        let key = try XCTUnwrap(keyMaterial)
        let replayBody = AuroraMeshPlainBody(
            kind: .text,
            sender: pair.aliceIdentity.identity,
            senderSequence: 2,
            createdAt: Date(),
            text: "different packet id"
        )
        let signed = try AuroraMeshCrypto.sign(replayBody, privateKey: pair.aliceIdentity.signingPrivateKey)
        let replay = AuroraMeshWirePacket(
            kind: .groupEnvelope,
            groupTag: AuroraMeshCrypto.groupTag(groupKey: key, epoch: 1),
            messageID: replayBody.messageID,
            ttl: 7,
            payload: try AuroraMeshCrypto.seal(signed, groupID: pair.group.id, epoch: 1, groupKey: key)
        )
        await XCTAssertThrowsErrorAsync(try await pair.bob.ingest(replay)) { error in
            XCTAssertEqual(error as? AuroraMeshError, .sequenceReplay)
        }
    }

    func testForgedMembershipGrantIsRejected() async throws {
        let pair = try await makeJoinedPair()
        let attacker = try AuroraMeshCrypto.makeIdentity(displayName: "Attacker")
        let forgedGrant = try AuroraMeshCrypto.makeGrant(
            groupID: pair.group.id,
            epoch: 1,
            member: attacker.identity,
            inviter: attacker,
            issuedAt: Date()
        )
        let body = AuroraMeshPlainBody(
            kind: .memberGrant,
            sender: pair.aliceIdentity.identity,
            senderSequence: 2,
            createdAt: Date(),
            memberGrant: forgedGrant
        )
        let keyMaterial = await pair.alice.keyMaterial(groupID: pair.group.id, epoch: 1)
        let key = try XCTUnwrap(keyMaterial)
        let signed = try AuroraMeshCrypto.sign(body, privateKey: pair.aliceIdentity.signingPrivateKey)
        let packet = AuroraMeshWirePacket(
            kind: .groupEnvelope,
            groupTag: AuroraMeshCrypto.groupTag(groupKey: key, epoch: 1),
            messageID: body.messageID,
            ttl: 7,
            payload: try AuroraMeshCrypto.seal(signed, groupID: pair.group.id, epoch: 1, groupKey: key)
        )
        await XCTAssertThrowsErrorAsync(try await pair.bob.ingest(packet)) { error in
            XCTAssertEqual(error as? AuroraMeshError, .verificationFailed)
        }
    }

    func testWireAndNameLimitsFailClosed() async throws {
        let oversized = AuroraMeshWirePacket(
            kind: .inviteHello,
            groupTag: Data(repeating: 0, count: 8),
            messageID: UUID(),
            ttl: 1,
            payload: Data(repeating: 0, count: AuroraMeshLimits.maximumControlPayloadBytes + 1)
        )
        XCTAssertThrowsError(try AuroraMeshWireCodec.encode(oversized))
        XCTAssertThrowsError(
            try AuroraMeshCrypto.makeIdentity(
                displayName: String(repeating: "x", count: AuroraMeshLimits.maximumDisplayNameBytes + 1)
            )
        )
        let engine = try makeEngine(identity: AuroraMeshCrypto.makeIdentity(displayName: "Alice"))
        await XCTAssertThrowsErrorAsync(
            try await engine.createGroup(
                name: String(repeating: "x", count: AuroraMeshLimits.maximumGroupNameBytes + 1)
            )
        ) { error in
            XCTAssertEqual(error as? AuroraMeshError, .invalidName)
        }
    }

    func testDisplayNameUpdatePreservesIdentityPropagatesAndKeepsNewestName() async throws {
        let pair = try await makeJoinedPair()
        let renamed = try AuroraMeshCrypto.identity(
            displayName: "Alicia",
            signingPrivateKey: pair.aliceIdentity.signingPrivateKey,
            agreementPrivateKey: pair.aliceIdentity.agreementPrivateKey
        )
        XCTAssertEqual(renamed.identity.id, pair.aliceIdentity.identity.id)
        XCTAssertEqual(renamed.signingPrivateKey, pair.aliceIdentity.signingPrivateKey)
        XCTAssertEqual(renamed.agreementPrivateKey, pair.aliceIdentity.agreementPrivateKey)

        let firstEvents = try await pair.alice.updateIdentity(renamed)
        let firstPacket = try XCTUnwrap(transmissions(in: firstEvents).first)
        let renamedAgain = try AuroraMeshCrypto.identity(
            displayName: "Ally",
            signingPrivateKey: pair.aliceIdentity.signingPrivateKey,
            agreementPrivateKey: pair.aliceIdentity.agreementPrivateKey
        )
        let secondEvents = try await pair.alice.updateIdentity(renamedAgain)
        let secondPacket = try XCTUnwrap(transmissions(in: secondEvents).first)

        let summaries = try await pair.bob.makeSyncSummaryPackets()
        let summary = try XCTUnwrap(summaries.first)
        let catchUp = try await pair.alice.ingest(summary)
        let catchUpIDs = Set(transmissions(in: catchUp).map(\.messageID))
        XCTAssertTrue(catchUpIDs.contains(firstPacket.messageID))
        XCTAssertTrue(catchUpIDs.contains(secondPacket.messageID))

        _ = try await pair.bob.ingest(secondPacket)
        _ = try await pair.bob.ingest(firstPacket)
        let snapshot = await pair.bob.snapshot()
        XCTAssertEqual(
            snapshot.displayNamesByGroup[pair.group.id]?[pair.aliceIdentity.identity.id],
            "Ally"
        )

        let store = try makeStore()
        try store.recordDisplayName("Newest", groupID: pair.group.id, memberID: "member", sequence: 2)
        try store.recordDisplayName("Older", groupID: pair.group.id, memberID: "member", sequence: 1)
        XCTAssertEqual(try store.displayNamesByGroup()[pair.group.id]?["member"], "Newest")
    }

    func testPresenceExpiresAndCatchUpExcludesPreJoinHistory() async throws {
        let clock = MutableClock(Date(timeIntervalSince1970: 10_000))
        let aliceIdentity = try AuroraMeshCrypto.makeIdentity(displayName: "Alice")
        let bobIdentity = try AuroraMeshCrypto.makeIdentity(displayName: "Bob")
        let alice = try makeEngine(identity: aliceIdentity, now: { clock.value })
        let bob = try makeEngine(identity: bobIdentity, now: { clock.value })
        let group = try await alice.createGroup(name: "Catch Up")
        _ = try await alice.sendText("before joining", groupID: group.id)
        clock.value.addTimeInterval(1)
        let invitation = try await alice.makeInvitation(groupID: group.id)
        let context = try await bob.makeJoinContext(for: invitation)
        let approval = try await alice.approve(context.request)
        _ = try await bob.consume(approval.approval, invitation: invitation, context: context)
        clock.value.addTimeInterval(1)
        _ = try await alice.sendText("after joining", groupID: group.id)

        let summaries = try await bob.makeSyncSummaryPackets()
        let summary = try XCTUnwrap(summaries.first)
        let catchUpEvents = try await alice.ingest(summary)
        let catchUp = transmissions(in: catchUpEvents).filter { $0.messageID != summary.messageID }
        XCTAssertEqual(catchUp.count, 1)
        _ = try await bob.ingest(try XCTUnwrap(catchUp.first))
        let messages = await bob.snapshot().messagesByGroup[group.id] ?? []
        XCTAssertEqual(messages.map(\.text), ["after joining"])
        let reachableSnapshot = await alice.snapshot()
        XCTAssertTrue(reachableSnapshot.reachableMemberIDs.contains(bobIdentity.identity.id))

        clock.value.addTimeInterval(AuroraMeshLimits.presenceLifetime + 0.001)
        let expiredSnapshot = await alice.snapshot()
        XCTAssertFalse(expiredSnapshot.reachableMemberIDs.contains(bobIdentity.identity.id))
    }

    func testCreatorRemovalRotatesEpochAndExcludesRemovedMember() async throws {
        let pair = try await makeJoinedPair()
        let rekey = try await pair.alice.removeMember(memberID: pair.bobIdentity.identity.id, groupID: pair.group.id)
        let rekeyPacket = try XCTUnwrap(transmissions(in: rekey).first)
        await XCTAssertThrowsErrorAsync(try await pair.bob.ingest(rekeyPacket)) { error in
            XCTAssertEqual(error as? AuroraMeshError, .unauthorized)
        }
        let newMessageEvents = try await pair.alice.sendText("After removal", groupID: pair.group.id)
        let newMessage = try XCTUnwrap(transmissions(in: newMessageEvents).first)
        await XCTAssertThrowsErrorAsync(try await pair.bob.ingest(newMessage)) { error in
            XCTAssertEqual(error as? AuroraMeshError, .unauthorized)
        }
        let snapshot = await pair.alice.snapshot()
        XCTAssertEqual(snapshot.groups.first?.epoch, 2)
    }

    func testCreatorDeletionHidesScrubsRelaysAcrossRestartAndPurgesAfterSevenDays() async throws {
        let clock = MutableClock(Date(timeIntervalSince1970: 30_000))
        let aliceIdentity = try AuroraMeshCrypto.makeIdentity(displayName: "Alice")
        let bobIdentity = try AuroraMeshCrypto.makeIdentity(displayName: "Bob")
        let aliceStore = try makeStore()
        let bobStore = try makeStore()
        let alice = try AuroraMeshEngine(identity: aliceIdentity, store: aliceStore, now: { clock.value })
        let bob = try AuroraMeshEngine(identity: bobIdentity, store: bobStore, now: { clock.value })
        let group = try await alice.createGroup(name: "Delete Me")
        let keyMaterial = await alice.keyMaterial(groupID: group.id, epoch: group.epoch)
        let key = try XCTUnwrap(keyMaterial)
        try aliceStore.recordKeyEpoch(groupID: group.id, epoch: group.epoch)
        let invite = try await alice.makeInvitation(groupID: group.id)
        let context = try await bob.makeJoinContext(for: invite)
        let approval = try await alice.approve(context.request)
        _ = try await bob.consume(approval.approval, invitation: invite, context: context)
        try bobStore.recordKeyEpoch(groupID: group.id, epoch: group.epoch)

        let messageEvents = try await alice.sendText("private", groupID: group.id)
        let message = try XCTUnwrap(transmissions(in: messageEvents).first)
        _ = try await bob.ingest(message)
        let acknowledgementEvents = try await bob.flushAcknowledgements(groupID: group.id)
        let acknowledgement = try XCTUnwrap(transmissions(in: acknowledgementEvents).first)
        _ = try await alice.ingest(acknowledgement)
        try aliceStore.recordDisplayName("Alice", groupID: group.id, memberID: aliceIdentity.identity.id, sequence: 99)

        await XCTAssertThrowsErrorAsync(try await bob.endGroup(groupID: group.id)) { error in
            XCTAssertEqual(error as? AuroraMeshError, .unauthorized)
        }
        let deletionEvents = try await alice.endGroup(groupID: group.id)
        let deletion = try XCTUnwrap(transmissions(in: deletionEvents).first)
        let deletedSnapshot = await alice.snapshot()
        XCTAssertTrue(deletedSnapshot.groups.isEmpty)
        XCTAssertNil(deletedSnapshot.messagesByGroup[group.id])
        XCTAssertTrue(try aliceStore.displayNamesByGroup()[group.id]?.isEmpty ?? true)
        XCTAssertTrue(try aliceStore.acknowledgementMemberIDs(messageID: message.messageID).isEmpty)
        XCTAssertEqual(try aliceStore.envelopes(groupID: group.id, since: .distantPast).map(\.packet.messageID), [deletion.messageID])

        let pending = try await alice.pendingTerminationPackets()
        XCTAssertEqual(pending.map(\.messageID), [deletion.messageID])
        XCTAssertEqual(pending.first?.ttl, AuroraMeshLimits.maximumHops)

        let restarted = try AuroraMeshEngine(
            identity: aliceIdentity,
            store: aliceStore,
            groupKeys: [group.id: [group.epoch: key]],
            now: { clock.value }
        )
        let restartedPending = try await restarted.pendingTerminationPackets()
        XCTAssertEqual(restartedPending.map(\.messageID), [deletion.messageID])
        _ = try await bob.ingest(try XCTUnwrap(restartedPending.first))
        let bobDeletedSnapshot = await bob.snapshot()
        XCTAssertTrue(bobDeletedSnapshot.groups.isEmpty)

        clock.value.addTimeInterval(AuroraMeshLimits.catchUpInterval + 0.001)
        let expiredPending = try await restarted.pendingTerminationPackets()
        XCTAssertTrue(expiredPending.isEmpty)
        let expiredCleanups = try await restarted.pendingGroupCleanups()
        let cleanup = try XCTUnwrap(expiredCleanups.first)
        XCTAssertTrue(cleanup.removesGroup)
        XCTAssertEqual(cleanup.epochs, [group.epoch])
        try await restarted.completeGroupCleanup(cleanup)
        XCTAssertTrue(try aliceStore.groups().isEmpty)
        let completedCleanups = try await restarted.pendingGroupCleanups()
        XCTAssertTrue(completedCleanups.isEmpty)
    }

    func testDeletionRejectsForgedTamperedAndWrongEpochPacketsAndCleansHistoricalKeys() async throws {
        let pair = try await makeJoinedPair()
        let keyMaterial = await pair.alice.keyMaterial(groupID: pair.group.id, epoch: pair.group.epoch)
        let key = try XCTUnwrap(keyMaterial)
        let forgedBody = AuroraMeshPlainBody(
            kind: .endGroup,
            sender: pair.bobIdentity.identity,
            senderSequence: 1,
            createdAt: Date()
        )
        let forgedSigned = try AuroraMeshCrypto.sign(forgedBody, privateKey: pair.bobIdentity.signingPrivateKey)
        let forged = AuroraMeshWirePacket(
            kind: .groupEnvelope,
            groupTag: AuroraMeshCrypto.groupTag(groupKey: key, epoch: pair.group.epoch),
            messageID: forgedBody.messageID,
            ttl: AuroraMeshLimits.maximumHops,
            payload: try AuroraMeshCrypto.seal(
                forgedSigned,
                groupID: pair.group.id,
                epoch: pair.group.epoch,
                groupKey: key
            )
        )
        await XCTAssertThrowsErrorAsync(try await pair.alice.ingest(forged)) { error in
            XCTAssertEqual(error as? AuroraMeshError, .unauthorized)
        }
        let activeSnapshot = await pair.alice.snapshot()
        XCTAssertEqual(activeSnapshot.groups.count, 1)

        let validEvents = try await pair.alice.endGroup(groupID: pair.group.id)
        let valid = try XCTUnwrap(transmissions(in: validEvents).first)
        var tamperedPayload = valid.payload
        tamperedPayload[tamperedPayload.startIndex] ^= 1
        let tampered = AuroraMeshWirePacket(
            kind: valid.kind,
            groupTag: valid.groupTag,
            messageID: valid.messageID,
            ttl: valid.ttl,
            payload: tamperedPayload
        )
        await XCTAssertThrowsErrorAsync(try await pair.bob.ingest(tampered))
        let wrongEpoch = AuroraMeshWirePacket(
            kind: valid.kind,
            groupTag: AuroraMeshCrypto.groupTag(groupKey: key, epoch: pair.group.epoch + 1),
            messageID: valid.messageID,
            ttl: valid.ttl,
            payload: valid.payload
        )
        await XCTAssertThrowsErrorAsync(try await pair.bob.ingest(wrongEpoch)) { error in
            XCTAssertEqual(error as? AuroraMeshError, .unauthorized)
        }
        _ = try await pair.bob.ingest(valid)

        await pair.alice.installKey(Data(repeating: 7, count: 32), groupID: pair.group.id, epoch: 0)
        let cleanups = try await pair.alice.pendingGroupCleanups()
        let cleanup = try XCTUnwrap(cleanups.first)
        XCTAssertFalse(cleanup.removesGroup)
        XCTAssertEqual(cleanup.epochs, [0])
        try await pair.alice.completeGroupCleanup(cleanup)
        let removedKey = await pair.alice.keyMaterial(groupID: pair.group.id, epoch: 0)
        let retainedKey = await pair.alice.keyMaterial(groupID: pair.group.id, epoch: pair.group.epoch)
        XCTAssertNil(removedKey)
        XCTAssertEqual(retainedKey, key)
    }

#if !SWIFT_PACKAGE
    func testConversationLayoutGroupsOnlyForwardSameSenderMessagesWithinFiveMinutes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 1_788_343_200)
        let messages = [
            conversationMessage(senderID: "alice", sequence: 1, date: start),
            conversationMessage(senderID: "alice", sequence: 2, date: start.addingTimeInterval(300)),
            conversationMessage(senderID: "alice", sequence: 3, date: start.addingTimeInterval(601)),
            conversationMessage(senderID: "bob", sequence: 1, date: start.addingTimeInterval(602)),
            conversationMessage(senderID: "bob", sequence: 2, date: start.addingTimeInterval(601)),
            conversationMessage(senderID: "bob", sequence: 3, date: start.addingTimeInterval(86_400)),
        ]

        let items = MeshConversationLayout.items(messages: messages, calendar: calendar)
        let contexts = items.compactMap { item -> MeshConversationMessageContext? in
            guard case let .message(context) = item else { return nil }
            return context
        }
        let days = items.compactMap { item -> Date? in
            guard case let .day(_, date) = item else { return nil }
            return date
        }

        XCTAssertEqual(contexts.map(\.message.id), messages.map(\.id))
        XCTAssertEqual(contexts.map(\.beginsGroup), [true, false, true, true, true, true])
        XCTAssertEqual(contexts.map(\.endsGroup), [false, true, true, true, true, true])
        XCTAssertEqual(days.count, 2)
    }

    func testConversationDateLabelsAndUTF8DraftValidation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_788_393_600)
        XCTAssertEqual(
            MeshConversationLayout.dayLabel(for: now, now: now, calendar: calendar, locale: Locale(identifier: "en_US_POSIX")),
            "Today"
        )
        XCTAssertEqual(
            MeshConversationLayout.dayLabel(
                for: now.addingTimeInterval(-86_400),
                now: now,
                calendar: calendar,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "Yesterday"
        )

        XCTAssertFalse(MeshConversationLayout.validateDraft(" \n ").canSend)
        XCTAssertFalse(MeshConversationLayout.validateDraft(String(repeating: "a", count: 1_535)).showsCount)
        let visible = MeshConversationLayout.validateDraft(String(repeating: "a", count: 1_536))
        XCTAssertTrue(visible.canSend)
        XCTAssertTrue(visible.showsCount)
        XCTAssertEqual(visible.tone, .normal)
        XCTAssertEqual(
            MeshConversationLayout.validateDraft(String(repeating: "a", count: 1_843)).tone,
            .warning
        )
        let exactUnicode = MeshConversationLayout.validateDraft(String(repeating: "🙂", count: 512))
        XCTAssertEqual(exactUnicode.byteCount, AuroraMeshLimits.maximumTextBytes)
        XCTAssertTrue(exactUnicode.canSend)
        let oversizedUnicode = MeshConversationLayout.validateDraft(String(repeating: "🙂", count: 513))
        XCTAssertFalse(oversizedUnicode.canSend)
        XCTAssertEqual(oversizedUnicode.tone, .overLimit)
    }
#endif

    func testStorePagesHistoryCapsCatchUpAndPreventsRestoration() async throws {
        let identity = try AuroraMeshCrypto.makeIdentity(displayName: "Alice")
        let store = try makeStore()
        let engine = try AuroraMeshEngine(identity: identity, store: store)
        let group = try await engine.createGroup(name: "Persistence")
        for index in 0..<30 {
            _ = try await engine.sendText("message \(index)", groupID: group.id)
        }
        XCTAssertEqual(try store.historyPage(groupID: group.id, limit: 1_000).count, 30)
        XCTAssertLessThanOrEqual(try store.envelopes(groupID: group.id, since: .distantPast, limit: 2_000).count, 500)
        try await engine.deleteLocalHistory(groupID: group.id)
        XCTAssertTrue(try store.historyPage(groupID: group.id).isEmpty)
        XCTAssertTrue(try store.envelopes(groupID: group.id, since: .distantPast).isEmpty)
    }

    func testDeterministicTopologiesAtMostOnceSevenHopAndDeliveryBound() async throws {
        let fixture = try await makeTwentyNodeFixture()
        let topologies = [
            line(count: 20),
            ring(count: 20),
            star(count: 20),
            sixNeighborDense(count: 20),
            partitioned(count: 20),
        ]
        for (index, graph) in topologies.enumerated() {
            let sendEvents = try await fixture.engines[0].sendText("topology \(index)", groupID: fixture.group.id)
            let message = try XCTUnwrap(transmissions(in: sendEvents).first)
            let outcome = await relay(message, through: graph, engines: fixture.engines)
            XCTAssertLessThanOrEqual(outcome.linkDeliveries, 120)
            XCTAssertEqual(outcome.displayCounts.values.max() ?? 0, 1)
            if index == 0 {
                XCTAssertTrue(outcome.displayCounts.keys.contains(7))
                XCTAssertFalse(outcome.displayCounts.keys.contains(8))
            }
            if index == 4 {
                XCTAssertTrue(outcome.displayCounts.keys.allSatisfy { $0 < 10 })
            }
        }
    }

    func testReleaseOptimizedThousandMessageSimulationPerformance() async throws {
#if AURORA_MESH_PERFORMANCE
        let clock = MutableClock(Date(timeIntervalSince1970: 20_000))
        let fixture = try await makeTwentyNodeFixture(now: { clock.value })
        let graph = sixNeighborDense(count: 20)
        let started = ContinuousClock.now
        for index in 0..<1_000 {
            clock.value.addTimeInterval(2.1)
            let events = try await fixture.engines[0].sendText("benchmark \(index)", groupID: fixture.group.id)
            let packet = try XCTUnwrap(transmissions(in: events).first)
            let outcome = await relay(packet, through: graph, engines: fixture.engines)
            XCTAssertLessThanOrEqual(outcome.linkDeliveries, 120)
            XCTAssertEqual(outcome.displayCounts.count, 19)
        }
        let elapsed = started.duration(to: .now)
        let components = elapsed.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        XCTAssertLessThan(seconds, 5, "Release simulation took \(seconds) seconds")
#else
        throw XCTSkip("Run the dedicated Release Mesh performance command documented in the handoff.")
#endif
    }

    private struct Pair {
        let alice: AuroraMeshEngine
        let bob: AuroraMeshEngine
        let aliceIdentity: AuroraMeshPrivateIdentity
        let bobIdentity: AuroraMeshPrivateIdentity
        let group: AuroraMeshGroup
    }

    private func makeJoinedPair() async throws -> Pair {
        let aliceIdentity = try AuroraMeshCrypto.makeIdentity(displayName: "Alice")
        let bobIdentity = try AuroraMeshCrypto.makeIdentity(displayName: "Bob")
        let alice = try makeEngine(identity: aliceIdentity)
        let bob = try makeEngine(identity: bobIdentity)
        let group = try await alice.createGroup(name: "Team")
        let invite = try await alice.makeInvitation(groupID: group.id)
        let context = try await bob.makeJoinContext(for: invite)
        let result = try await alice.approve(context.request)
        _ = try await bob.consume(result.approval, invitation: invite, context: context)
        return Pair(
            alice: alice,
            bob: bob,
            aliceIdentity: aliceIdentity,
            bobIdentity: bobIdentity,
            group: group
        )
    }

    private func makeEngine(
        identity: AuroraMeshPrivateIdentity,
        now: @escaping AuroraMeshEngine.Clock = { Date() }
    ) throws -> AuroraMeshEngine {
        try AuroraMeshEngine(identity: identity, store: makeStore(), now: now)
    }

    private func makeStore() throws -> AuroraMeshStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aurora-mesh-tests-\(UUID().uuidString)")
            .appendingPathComponent("mesh.sqlite")
        return try AuroraMeshStore(databaseURL: url)
    }

#if !SWIFT_PACKAGE
    private func conversationMessage(senderID: String, sequence: UInt64, date: Date) -> AuroraMeshMessage {
        AuroraMeshMessage(
            id: UUID(),
            groupID: UUID(),
            epoch: 1,
            senderID: senderID,
            senderSequence: sequence,
            createdAt: date,
            firstSeenAt: date,
            text: "Message \(sequence)",
            expectedRecipients: 1
        )
    }
#endif

    private func transmissions(in events: [AuroraMeshEngineEvent]) -> [AuroraMeshWirePacket] {
        events.compactMap { event in
            guard case let .transmit(packet) = event else { return nil }
            return packet
        }
    }

    private struct Fixture {
        let engines: [AuroraMeshEngine]
        let group: AuroraMeshGroup
    }

    private func makeTwentyNodeFixture(
        now: @escaping AuroraMeshEngine.Clock = { Date() }
    ) async throws -> Fixture {
        let identities = try (0..<20).map { try AuroraMeshCrypto.makeIdentity(displayName: "Node \($0)") }
        let groupID = UUID()
        let creator = identities[0]
        let grants = try identities.map {
            try AuroraMeshCrypto.makeGrant(
                groupID: groupID,
                epoch: 1,
                member: $0.identity,
                inviter: creator,
                issuedAt: Date()
            )
        }
        let group = AuroraMeshGroup(id: groupID, name: "Simulation", creatorID: creator.identity.id, members: grants)
        let key = AuroraMeshCrypto.randomGroupKey()
        var engines: [AuroraMeshEngine] = []
        for identity in identities {
            let store = try makeStore()
            try store.save(group: group)
            engines.append(try AuroraMeshEngine(
                identity: identity,
                store: store,
                groupKeys: [groupID: [1: key]],
                now: now
            ))
        }
        return Fixture(engines: engines, group: group)
    }

    private struct RelayOutcome {
        var displayCounts: [Int: Int]
        var linkDeliveries: Int
    }

    private func relay(
        _ packet: AuroraMeshWirePacket,
        through graph: [[Int]],
        engines: [AuroraMeshEngine]
    ) async -> RelayOutcome {
        var queue = graph[0].map { (0, $0, packet) }
        var counts: [Int: Int] = [:]
        var deliveries = 0
        while !queue.isEmpty, deliveries <= 120 {
            let (from, node, incoming) = queue.removeFirst()
            deliveries += 1
            do {
                let events = try await engines[node].ingest(incoming)
                if events.contains(where: {
                    if case .receivedMessage = $0 { return true }
                    return false
                }) { counts[node, default: 0] += 1 }
                guard let relayed = transmissions(in: events).first(where: { $0.messageID == packet.messageID }) else { continue }
                queue.append(contentsOf: graph[node].filter { $0 != from }.map { (node, $0, relayed) })
            } catch {
                continue
            }
        }
        return RelayOutcome(displayCounts: counts, linkDeliveries: deliveries)
    }

    private func line(count: Int) -> [[Int]] {
        (0..<count).map { node in [node - 1, node + 1].filter { $0 >= 0 && $0 < count } }
    }

    private func ring(count: Int) -> [[Int]] {
        (0..<count).map { [($0 - 1 + count) % count, ($0 + 1) % count] }
    }

    private func star(count: Int) -> [[Int]] {
        (0..<count).map { node in node == 0 ? Array(1..<min(count, 7)) : (node < 7 ? [0] : []) }
    }

    private func sixNeighborDense(count: Int) -> [[Int]] {
        (0..<count).map { node in
            Array(1...3).flatMap { distance in
                [(node - distance + count) % count, (node + distance) % count]
            }
        }
    }

    private func partitioned(count: Int) -> [[Int]] {
        (0..<count).map { node in
            let range = node < count / 2 ? 0..<(count / 2) : (count / 2)..<count
            return [node - 1, node + 1].filter { range.contains($0) }
        }
    }
}


private final class MutableClock: @unchecked Sendable {
    var value: Date
    init(_ value: Date) { self.value = value }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error")
    } catch {
        handler(error)
    }
}
#endif
