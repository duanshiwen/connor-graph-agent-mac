import Foundation
import Security

public protocol CredentialStore: Sendable {
    func saveSecret(_ secret: String, service: String, account: String) throws
    func readSecret(service: String, account: String) throws -> String?
    func deleteSecret(service: String, account: String) throws
}

public enum KeychainCredentialStoreError: Error, Sendable, Equatable, CustomStringConvertible {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var description: String {
        switch self {
        case .unexpectedStatus(let status): "unexpectedStatus(\(status))"
        case .invalidData: "invalidData"
        }
    }
}

public struct KeychainCredentialStore: CredentialStore, Sendable, Equatable {
    public init() {}

    public func saveSecret(_ secret: String, service: String, account: String) throws {
        let data = Data(secret.utf8)
        let query = baseQuery(service: service, account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainCredentialStoreError.unexpectedStatus(addStatus)
            }
            return
        }
        throw KeychainCredentialStoreError.unexpectedStatus(status)
    }

    public func readSecret(service: String, account: String) throws -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw KeychainCredentialStoreError.invalidData
        }
        return secret
    }

    public func deleteSecret(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
