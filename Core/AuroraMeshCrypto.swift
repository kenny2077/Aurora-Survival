#if AURORA_MESH_BETA
import CryptoKit
import Foundation

public enum AuroraMeshCrypto {
    public static func makeIdentity(displayName: String) throws -> AuroraMeshPrivateIdentity {
        let signing = Curve25519.Signing.PrivateKey()
        let agreement = Curve25519.KeyAgreement.PrivateKey()
        return try identity(
            displayName: displayName,
            signingPrivateKey: signing.rawRepresentation,
            agreementPrivateKey: agreement.rawRepresentation
        )
    }

    public static func identity(
        displayName: String,
        signingPrivateKey: Data,
        agreementPrivateKey: Data
    ) throws -> AuroraMeshPrivateIdentity {
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              cleanName.lengthOfBytes(using: .utf8) <= AuroraMeshLimits.maximumDisplayNameBytes
        else { throw AuroraMeshError.invalidName }
        let signing = try Curve25519.Signing.PrivateKey(rawRepresentation: signingPrivateKey)
        let agreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: agreementPrivateKey)
        let signingPublic = signing.publicKey.rawRepresentation
        let fingerprint = SHA256.hash(data: signingPublic).map { String(format: "%02x", $0) }.joined()
        return AuroraMeshPrivateIdentity(
            identity: AuroraMeshIdentity(
                id: fingerprint,
                displayName: cleanName,
                signingPublicKey: signingPublic,
                agreementPublicKey: agreement.publicKey.rawRepresentation
            ),
            signingPrivateKey: signing.rawRepresentation,
            agreementPrivateKey: agreement.rawRepresentation
        )
    }

    public static func randomGroupKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public static func groupTag(groupKey: Data, epoch: Int) -> Data {
        let key = SymmetricKey(data: groupKey)
        let value = Data("aurora-mesh-group:\(epoch)".utf8)
        return Data(HMAC<SHA256>.authenticationCode(for: value, using: key).prefix(8))
    }

    public static func sign(_ body: AuroraMeshPlainBody, privateKey: Data) throws -> AuroraMeshSignedBody {
        let encoded = try canonicalEncoder.encode(body)
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
        return AuroraMeshSignedBody(body: body, signature: try key.signature(for: encoded))
    }

    public static func verify(_ signed: AuroraMeshSignedBody) -> Bool {
        guard let encoded = try? canonicalEncoder.encode(signed.body),
              let key = try? Curve25519.Signing.PublicKey(
                rawRepresentation: signed.body.sender.signingPublicKey
              )
        else { return false }
        return key.isValidSignature(signed.signature, for: encoded)
    }

    public static func seal(
        _ signedBody: AuroraMeshSignedBody,
        groupID: UUID,
        epoch: Int,
        groupKey: Data
    ) throws -> Data {
        let plaintext = try canonicalEncoder.encode(signedBody)
        let sealed = try ChaChaPoly.seal(
            plaintext,
            using: SymmetricKey(data: groupKey),
            authenticating: authenticatedContext(groupID: groupID, epoch: epoch)
        )
        return sealed.combined
    }

    public static func open(
        _ data: Data,
        groupID: UUID,
        epoch: Int,
        groupKey: Data
    ) throws -> AuroraMeshSignedBody {
        do {
            let box = try ChaChaPoly.SealedBox(combined: data)
            let plaintext = try ChaChaPoly.open(
                box,
                using: SymmetricKey(data: groupKey),
                authenticating: authenticatedContext(groupID: groupID, epoch: epoch)
            )
            let body = try decoder.decode(AuroraMeshSignedBody.self, from: plaintext)
            guard verify(body) else { throw AuroraMeshError.verificationFailed }
            return body
        } catch let error as AuroraMeshError {
            throw error
        } catch {
            throw AuroraMeshError.cryptographyFailed
        }
    }

    public static func makeGrant(
        groupID: UUID,
        epoch: Int,
        member: AuroraMeshIdentity,
        inviter: AuroraMeshPrivateIdentity,
        issuedAt: Date
    ) throws -> AuroraMeshMemberGrant {
        let unsigned = GrantUnsigned(
            groupID: groupID,
            epoch: epoch,
            member: member,
            inviterID: inviter.identity.id,
            issuedAt: issuedAt
        )
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: inviter.signingPrivateKey)
        return AuroraMeshMemberGrant(
            groupID: groupID,
            epoch: epoch,
            member: member,
            inviterID: inviter.identity.id,
            issuedAt: issuedAt,
            signature: try key.signature(for: canonicalEncoder.encode(unsigned))
        )
    }

    public static func verifyGrant(
        _ grant: AuroraMeshMemberGrant,
        inviter: AuroraMeshIdentity
    ) -> Bool {
        let unsigned = GrantUnsigned(
            groupID: grant.groupID,
            epoch: grant.epoch,
            member: grant.member,
            inviterID: grant.inviterID,
            issuedAt: grant.issuedAt
        )
        guard inviter.id == grant.inviterID,
              let data = try? canonicalEncoder.encode(unsigned),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: inviter.signingPublicKey)
        else { return false }
        return key.isValidSignature(grant.signature, for: data)
    }

    public static func ephemeralPrivateKey() -> Data {
        Curve25519.KeyAgreement.PrivateKey().rawRepresentation
    }

    public static func ephemeralPublicKey(privateKey: Data) throws -> Data {
        try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: privateKey
        ).publicKey.rawRepresentation
    }

    public static func invitationSessionKey(
        ownPrivateKey: Data,
        remotePublicKey: Data,
        invitationID: UUID
    ) throws -> SymmetricKey {
        let own = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: ownPrivateKey)
        let remote = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remotePublicKey)
        let secret = try own.sharedSecretFromKeyAgreement(with: remote)
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: uuidData(invitationID),
            sharedInfo: Data("aurora-mesh-invite-v1".utf8),
            outputByteCount: 32
        )
    }

    public static func verificationCode(
        key: SymmetricKey,
        invitationID: UUID,
        inviterEphemeralKey: Data,
        joinerEphemeralKey: Data
    ) -> String {
        var transcript = uuidData(invitationID)
        transcript.append(inviterEphemeralKey)
        transcript.append(joinerEphemeralKey)
        let digest = HMAC<SHA256>.authenticationCode(for: transcript, using: key)
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06d", value % 1_000_000)
    }

    public static func sealApproval(_ approval: AuroraMeshApprovalPayload, key: SymmetricKey) throws -> Data {
        let box = try ChaChaPoly.seal(try canonicalEncoder.encode(approval), using: key)
        return box.combined
    }

    public static func openApproval(_ data: Data, key: SymmetricKey) throws -> AuroraMeshApprovalPayload {
        let box = try ChaChaPoly.SealedBox(combined: data)
        return try decoder.decode(
            AuroraMeshApprovalPayload.self,
            from: ChaChaPoly.open(box, using: key)
        )
    }

    public static func sealGroupKey(
        _ groupKey: Data,
        senderAgreementPrivateKey: Data,
        recipientAgreementPublicKey: Data,
        groupID: UUID,
        epoch: Int
    ) throws -> Data {
        let key = try membershipKey(
            ownPrivateKey: senderAgreementPrivateKey,
            remotePublicKey: recipientAgreementPublicKey,
            groupID: groupID,
            epoch: epoch
        )
        return try ChaChaPoly.seal(
            groupKey,
            using: key,
            authenticating: authenticatedContext(groupID: groupID, epoch: epoch)
        ).combined
    }

    public static func openGroupKey(
        _ ciphertext: Data,
        recipientAgreementPrivateKey: Data,
        senderAgreementPublicKey: Data,
        groupID: UUID,
        epoch: Int
    ) throws -> Data {
        let key = try membershipKey(
            ownPrivateKey: recipientAgreementPrivateKey,
            remotePublicKey: senderAgreementPublicKey,
            groupID: groupID,
            epoch: epoch
        )
        return try ChaChaPoly.open(
            ChaChaPoly.SealedBox(combined: ciphertext),
            using: key,
            authenticating: authenticatedContext(groupID: groupID, epoch: epoch)
        )
    }

    private struct GrantUnsigned: Codable {
        let groupID: UUID
        let epoch: Int
        let member: AuroraMeshIdentity
        let inviterID: String
        let issuedAt: Date
    }

    private static func authenticatedContext(groupID: UUID, epoch: Int) -> Data {
        var data = uuidData(groupID)
        var value = Int64(epoch).bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        return data
    }

    private static func membershipKey(
        ownPrivateKey: Data,
        remotePublicKey: Data,
        groupID: UUID,
        epoch: Int
    ) throws -> SymmetricKey {
        let own = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: ownPrivateKey)
        let remote = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remotePublicKey)
        var salt = uuidData(groupID)
        var epochValue = Int64(epoch).bigEndian
        withUnsafeBytes(of: &epochValue) { salt.append(contentsOf: $0) }
        return try own.sharedSecretFromKeyAgreement(with: remote).hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data("aurora-mesh-membership-v1".utf8),
            outputByteCount: 32
        )
    }

    private static func uuidData(_ id: UUID) -> Data {
        var value = id.uuid
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    private static var canonicalEncoder: JSONEncoder {
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

public enum AuroraMeshWireCodec {
    private static let magic = Data([0x41, 0x4D, 0x53, 0x48])
    private static let headerSize = 33

    public static func encode(_ packet: AuroraMeshWirePacket) throws -> Data {
        guard packet.groupTag.count == 8,
              packet.ttl <= AuroraMeshLimits.maximumHops,
              packet.payload.count <= AuroraMeshLimits.maximumWirePayloadBytes,
              (packet.kind == .groupEnvelope
                  || packet.payload.count <= AuroraMeshLimits.maximumControlPayloadBytes)
        else { throw AuroraMeshError.invalidPacket }
        var result = Data(capacity: headerSize + packet.payload.count)
        result.append(magic)
        result.append(AuroraMeshLimits.protocolVersion)
        result.append(packet.kind.rawValue)
        result.append(packet.ttl)
        result.append(packet.groupTag)
        var uuid = packet.messageID.uuid
        withUnsafeBytes(of: &uuid) { result.append(contentsOf: $0) }
        var length = UInt16(packet.payload.count).bigEndian
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        result.append(packet.payload)
        return result
    }

    public static func decode(_ data: Data) throws -> AuroraMeshWirePacket {
        guard data.count >= headerSize,
              data.prefix(4) == magic,
              data[4] == AuroraMeshLimits.protocolVersion,
              let kind = AuroraMeshPacketKind(rawValue: data[5])
        else { throw AuroraMeshError.invalidPacket }
        let ttl = data[6]
        guard ttl <= AuroraMeshLimits.maximumHops else { throw AuroraMeshError.invalidPacket }
        let tag = data.subdata(in: 7..<15)
        let uuidBytes = Array(data[15..<31])
        let uuid = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
        let length = Int(UInt16(data[31]) << 8 | UInt16(data[32]))
        guard data.count == headerSize + length else { throw AuroraMeshError.invalidPacket }
        return AuroraMeshWirePacket(
            kind: kind,
            groupTag: tag,
            messageID: uuid,
            ttl: ttl,
            payload: Data(data.suffix(length))
        )
    }
}
#endif
