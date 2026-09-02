#if AURORA_MESH_BETA
import Foundation

public enum AuroraMeshLimits {
    public static let protocolVersion: UInt8 = 1
    public static let maximumMembers = 20
    public static let maximumDirectLinks = 6
    public static let maximumHops: UInt8 = 7
    public static let maximumTextBytes = 2_048
    public static let maximumDisplayNameBytes = 64
    public static let maximumGroupNameBytes = 80
    public static let maximumWirePayloadBytes = 16_384
    public static let maximumControlPayloadBytes = 8_192
    public static let maximumQueuedFrames = 256
    public static let maximumReassembliesPerPeer = 32
    public static let maximumRecentMessageIDs = 4_096
    public static let maximumSequenceReorderWindow: UInt64 = 4_096
    public static let maximumMessagesPerMinute = 30
    public static let maximumCatchUpMessages = 500
    public static let catchUpInterval: TimeInterval = 7 * 24 * 60 * 60
    public static let invitationLifetime: TimeInterval = 5 * 60
    public static let acknowledgementDelay: TimeInterval = 0.25
    public static let presenceInterval: TimeInterval = 20
    public static let presenceLifetime: TimeInterval = 45
}

public struct AuroraMeshIdentity: Codable, Hashable, Sendable {
    public let id: String
    public var displayName: String
    public let signingPublicKey: Data
    public let agreementPublicKey: Data

    public init(
        id: String,
        displayName: String,
        signingPublicKey: Data,
        agreementPublicKey: Data
    ) {
        self.id = id
        self.displayName = displayName
        self.signingPublicKey = signingPublicKey
        self.agreementPublicKey = agreementPublicKey
    }

    public var shortFingerprint: String {
        id.prefix(12).uppercased()
    }
}

public struct AuroraMeshPrivateIdentity: Sendable {
    public let identity: AuroraMeshIdentity
    public let signingPrivateKey: Data
    public let agreementPrivateKey: Data

    public init(
        identity: AuroraMeshIdentity,
        signingPrivateKey: Data,
        agreementPrivateKey: Data
    ) {
        self.identity = identity
        self.signingPrivateKey = signingPrivateKey
        self.agreementPrivateKey = agreementPrivateKey
    }
}

public struct AuroraMeshMemberGrant: Codable, Hashable, Sendable {
    public let groupID: UUID
    public let epoch: Int
    public let member: AuroraMeshIdentity
    public let inviterID: String
    public let issuedAt: Date
    public let signature: Data

    public init(
        groupID: UUID,
        epoch: Int,
        member: AuroraMeshIdentity,
        inviterID: String,
        issuedAt: Date,
        signature: Data
    ) {
        self.groupID = groupID
        self.epoch = epoch
        self.member = member
        self.inviterID = inviterID
        self.issuedAt = issuedAt
        self.signature = signature
    }
}

public struct AuroraMeshGroup: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let creatorID: String
    public var epoch: Int
    public var members: [AuroraMeshMemberGrant]
    public var endedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        creatorID: String,
        epoch: Int = 1,
        members: [AuroraMeshMemberGrant],
        endedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.creatorID = creatorID
        self.epoch = epoch
        self.members = members
        self.endedAt = endedAt
    }
}

public enum AuroraMeshDeliveryState: Codable, Equatable, Sendable {
    case sending
    case relayed
    case delivered(received: Int, expected: Int)
}

public struct AuroraMeshMessage: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let groupID: UUID
    public let epoch: Int
    public let senderID: String
    public let senderSequence: UInt64
    public let createdAt: Date
    public let firstSeenAt: Date
    public let text: String
    public let expectedRecipients: Int
    public var acknowledgedMemberIDs: Set<String>
    public var wasRelayed: Bool

    public init(
        id: UUID,
        groupID: UUID,
        epoch: Int,
        senderID: String,
        senderSequence: UInt64,
        createdAt: Date,
        firstSeenAt: Date,
        text: String,
        expectedRecipients: Int,
        acknowledgedMemberIDs: Set<String> = [],
        wasRelayed: Bool = false
    ) {
        self.id = id
        self.groupID = groupID
        self.epoch = epoch
        self.senderID = senderID
        self.senderSequence = senderSequence
        self.createdAt = createdAt
        self.firstSeenAt = firstSeenAt
        self.text = text
        self.expectedRecipients = expectedRecipients
        self.acknowledgedMemberIDs = acknowledgedMemberIDs
        self.wasRelayed = wasRelayed
    }

    public var deliveryState: AuroraMeshDeliveryState {
        if !acknowledgedMemberIDs.isEmpty {
            return .delivered(
                received: min(acknowledgedMemberIDs.count, expectedRecipients),
                expected: expectedRecipients
            )
        }
        return wasRelayed ? .relayed : .sending
    }
}

public enum AuroraMeshBodyKind: String, Codable, Sendable {
    case text
    case acknowledgement
    case identityUpdate
    case memberGrant
    case rekey
    case leave
    case endGroup
    case syncSummary
}

public struct AuroraMeshPlainBody: Codable, Hashable, Sendable {
    public let kind: AuroraMeshBodyKind
    public let messageID: UUID
    public let sender: AuroraMeshIdentity
    public let senderSequence: UInt64
    public let createdAt: Date
    public let text: String?
    public let expectedRecipients: Int
    public let acknowledgedMessageIDs: [UUID]
    public let memberGrant: AuroraMeshMemberGrant?
    public let payload: Data?

    public init(
        kind: AuroraMeshBodyKind,
        messageID: UUID = UUID(),
        sender: AuroraMeshIdentity,
        senderSequence: UInt64,
        createdAt: Date,
        text: String? = nil,
        expectedRecipients: Int = 0,
        acknowledgedMessageIDs: [UUID] = [],
        memberGrant: AuroraMeshMemberGrant? = nil,
        payload: Data? = nil
    ) {
        self.kind = kind
        self.messageID = messageID
        self.sender = sender
        self.senderSequence = senderSequence
        self.createdAt = createdAt
        self.text = text
        self.expectedRecipients = expectedRecipients
        self.acknowledgedMessageIDs = acknowledgedMessageIDs
        self.memberGrant = memberGrant
        self.payload = payload
    }
}

public struct AuroraMeshSignedBody: Codable, Hashable, Sendable {
    public let body: AuroraMeshPlainBody
    public let signature: Data
}

public enum AuroraMeshPacketKind: UInt8, Codable, Sendable {
    case groupEnvelope = 1
    case inviteHello = 2
    case inviteApproval = 3
}

public struct AuroraMeshWirePacket: Equatable, Sendable {
    public let kind: AuroraMeshPacketKind
    public let groupTag: Data
    public let messageID: UUID
    public var ttl: UInt8
    public let payload: Data

    public init(
        kind: AuroraMeshPacketKind,
        groupTag: Data,
        messageID: UUID,
        ttl: UInt8,
        payload: Data
    ) {
        self.kind = kind
        self.groupTag = groupTag
        self.messageID = messageID
        self.ttl = ttl
        self.payload = payload
    }
}

public struct AuroraMeshInvitation: Codable, Hashable, Sendable {
    public let version: UInt8
    public let invitationID: UUID
    public let groupID: UUID
    public let groupName: String
    public let epoch: Int
    public let inviter: AuroraMeshIdentity
    public let ephemeralPublicKey: Data
    public let expiresAt: Date
}

public struct AuroraMeshJoinRequest: Codable, Hashable, Sendable {
    public let invitationID: UUID
    public let joiner: AuroraMeshIdentity
    public let ephemeralPublicKey: Data
}

public struct AuroraMeshJoinContext: Sendable {
    public let request: AuroraMeshJoinRequest
    public let ephemeralPrivateKey: Data
    public let verificationCode: String
}

public struct AuroraMeshApprovalPayload: Codable, Sendable {
    public let group: AuroraMeshGroup
    public let groupKey: Data
    public let grant: AuroraMeshMemberGrant
}

public struct AuroraMeshInviteApproval: Codable, Sendable {
    public let invitationID: UUID
    public let ciphertext: Data

    public init(invitationID: UUID, ciphertext: Data) {
        self.invitationID = invitationID
        self.ciphertext = ciphertext
    }
}

public struct AuroraMeshApprovalResult: Sendable {
    public let approval: AuroraMeshInviteApproval
    public let events: [AuroraMeshEngineEvent]

    public init(approval: AuroraMeshInviteApproval, events: [AuroraMeshEngineEvent]) {
        self.approval = approval
        self.events = events
    }
}

public struct AuroraMeshRekeyPackage: Codable, Hashable, Sendable {
    public let recipientID: String
    public let ciphertext: Data

    public init(recipientID: String, ciphertext: Data) {
        self.recipientID = recipientID
        self.ciphertext = ciphertext
    }
}

public struct AuroraMeshRekeyPayload: Codable, Hashable, Sendable {
    public let group: AuroraMeshGroup
    public let packages: [AuroraMeshRekeyPackage]

    public init(group: AuroraMeshGroup, packages: [AuroraMeshRekeyPackage]) {
        self.group = group
        self.packages = packages
    }
}

public struct AuroraMeshSyncSummary: Codable, Hashable, Sendable {
    public let requesterID: String
    public let highestSequences: [String: UInt64]

    public init(requesterID: String, highestSequences: [String: UInt64]) {
        self.requesterID = requesterID
        self.highestSequences = highestSequences
    }
}

public enum AuroraMeshEngineEvent: Equatable, Sendable {
    case transmit(AuroraMeshWirePacket)
    case receivedMessage(groupID: UUID, messageID: UUID)
    case deliveryChanged(groupID: UUID, messageID: UUID)
    case acknowledgementPending(groupID: UUID)
}

public struct AuroraMeshGroupCleanup: Equatable, Sendable {
    public let groupID: UUID
    public let epochs: [Int]
    public let removesGroup: Bool

    public init(groupID: UUID, epochs: [Int], removesGroup: Bool) {
        self.groupID = groupID
        self.epochs = epochs
        self.removesGroup = removesGroup
    }
}

public struct AuroraMeshSnapshot: Equatable, Sendable {
    public var groups: [AuroraMeshGroup]
    public var messagesByGroup: [UUID: [AuroraMeshMessage]]
    public var reachableMemberIDs: Set<String>
    public var displayNamesByGroup: [UUID: [String: String]]

    public init(
        groups: [AuroraMeshGroup] = [],
        messagesByGroup: [UUID: [AuroraMeshMessage]] = [:],
        reachableMemberIDs: Set<String> = [],
        displayNamesByGroup: [UUID: [String: String]] = [:]
    ) {
        self.groups = groups
        self.messagesByGroup = messagesByGroup
        self.reachableMemberIDs = reachableMemberIDs
        self.displayNamesByGroup = displayNamesByGroup
    }
}

public enum AuroraMeshError: Error, Equatable {
    case invalidName
    case groupNotFound
    case groupEnded
    case memberLimitReached
    case messageTooLarge
    case invalidPacket
    case unsupportedVersion
    case duplicateMessage
    case expiredMessage
    case invitationExpired
    case invitationNotFound
    case invitationAlreadyUsed
    case verificationFailed
    case unauthorized
    case staleEpoch
    case rateLimited
    case sequenceReplay
    case cryptographyFailed
    case persistenceFailed
}
#endif
