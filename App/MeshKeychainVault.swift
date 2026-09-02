#if AURORA_MESH_BETA
import Foundation
import Security

final class MeshKeychainVault {
    private struct StoredIdentity: Codable {
        let displayName: String
        let signingPrivateKey: Data
        let agreementPrivateKey: Data
    }

    private let service = "com.example.AuroraSurvivalAgent.mesh.v1"

    func loadOrCreateIdentity(displayName: String) throws -> AuroraMeshPrivateIdentity {
        if let data = try read(account: "identity"),
           let stored = try? JSONDecoder().decode(StoredIdentity.self, from: data) {
            return try AuroraMeshCrypto.identity(
                displayName: stored.displayName,
                signingPrivateKey: stored.signingPrivateKey,
                agreementPrivateKey: stored.agreementPrivateKey
            )
        }
        let identity = try AuroraMeshCrypto.makeIdentity(displayName: displayName)
        try write(
            try JSONEncoder().encode(
                StoredIdentity(
                    displayName: identity.identity.displayName,
                    signingPrivateKey: identity.signingPrivateKey,
                    agreementPrivateKey: identity.agreementPrivateKey
                )
            ),
            account: "identity"
        )
        return identity
    }

    func updateDisplayName(_ displayName: String) throws -> AuroraMeshPrivateIdentity {
        guard let data = try read(account: "identity"),
              let stored = try? JSONDecoder().decode(StoredIdentity.self, from: data)
        else { throw AuroraMeshError.persistenceFailed }
        let updated = try AuroraMeshCrypto.identity(
            displayName: displayName,
            signingPrivateKey: stored.signingPrivateKey,
            agreementPrivateKey: stored.agreementPrivateKey
        )
        try write(
            try JSONEncoder().encode(
                StoredIdentity(
                    displayName: updated.identity.displayName,
                    signingPrivateKey: updated.signingPrivateKey,
                    agreementPrivateKey: updated.agreementPrivateKey
                )
            ),
            account: "identity"
        )
        return updated
    }

    func saveGroupKey(_ key: Data, groupID: UUID, epoch: Int) throws {
        try write(key, account: groupKeyAccount(groupID: groupID, epoch: epoch))
    }

    func groupKey(groupID: UUID, epoch: Int) throws -> Data? {
        try read(account: groupKeyAccount(groupID: groupID, epoch: epoch))
    }

    func deleteGroupKey(groupID: UUID, epoch: Int) throws {
        let status = SecItemDelete(baseQuery(account: groupKeyAccount(groupID: groupID, epoch: epoch)) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuroraMeshError.persistenceFailed
        }
    }

    private func groupKeyAccount(groupID: UUID, epoch: Int) -> String {
        "group.\(groupID.uuidString).epoch.\(epoch)"
    }

    private func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AuroraMeshError.persistenceFailed
        }
        return data
    }

    private func write(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw AuroraMeshError.persistenceFailed }
        var insertion = query
        insertion.merge(attributes) { _, new in new }
        guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
            throw AuroraMeshError.persistenceFailed
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
#endif
