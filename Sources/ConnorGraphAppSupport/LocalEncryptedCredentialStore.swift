import Foundation
import CryptoKit

public enum LocalEncryptedCredentialStoreError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidMasterKey
    case invalidRecord
    case decryptionFailed

    public var description: String {
        switch self {
        case .invalidMasterKey: "invalidMasterKey"
        case .invalidRecord: "invalidRecord"
        case .decryptionFailed: "decryptionFailed"
        }
    }
}

public struct LocalEncryptedCredentialStore: CredentialStore, @unchecked Sendable {
    public var rootDirectory: URL
    public var fileManager: FileManager

    public init(rootDirectory: URL = Self.defaultRootDirectory(), fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public static func defaultRootDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return AppStoragePaths
            .resolving(applicationSupportBaseDirectory: base)
            .configDirectory
            .appendingPathComponent("credentials", isDirectory: true)
    }

    public func saveSecret(_ secret: String, service: String, account: String) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let key = try loadOrCreateMasterKey()
        let sealedBox = try AES.GCM.seal(Data(secret.utf8), using: key)
        let record = EncryptedCredentialRecord(
            version: 1,
            algorithm: "AES.GCM",
            serviceHash: Self.hash(service),
            accountHash: Self.hash(account),
            nonce: Data(sealedBox.nonce).base64EncodedString(),
            ciphertext: sealedBox.ciphertext.base64EncodedString(),
            tag: sealedBox.tag.base64EncodedString()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: credentialURL(service: service, account: account), options: .atomic)
        try restrictPermissionsIfPossible(credentialURL(service: service, account: account))
    }

    public func readSecret(service: String, account: String) throws -> String? {
        let url = credentialURL(service: service, account: account)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let record = try JSONDecoder().decode(EncryptedCredentialRecord.self, from: Data(contentsOf: url))
        guard record.version == 1,
              record.algorithm == "AES.GCM",
              let nonceData = Data(base64Encoded: record.nonce),
              let ciphertext = Data(base64Encoded: record.ciphertext),
              let tag = Data(base64Encoded: record.tag) else {
            throw LocalEncryptedCredentialStoreError.invalidRecord
        }
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let plaintext = try AES.GCM.open(sealedBox, using: try loadOrCreateMasterKey())
            guard let secret = String(data: plaintext, encoding: .utf8) else {
                throw LocalEncryptedCredentialStoreError.invalidRecord
            }
            return secret
        } catch let error as LocalEncryptedCredentialStoreError {
            throw error
        } catch {
            throw LocalEncryptedCredentialStoreError.decryptionFailed
        }
    }

    public func deleteSecret(service: String, account: String) throws {
        let url = credentialURL(service: service, account: account)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private var masterKeyURL: URL { rootDirectory.appendingPathComponent("master.key") }

    private func credentialURL(service: String, account: String) -> URL {
        rootDirectory.appendingPathComponent("\(Self.hash(service + ":" + account)).json")
    }

    private func loadOrCreateMasterKey() throws -> SymmetricKey {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: masterKeyURL.path) {
            let encoded = try String(contentsOf: masterKeyURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = Data(base64Encoded: encoded), data.count == 32 else {
                throw LocalEncryptedCredentialStoreError.invalidMasterKey
            }
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try data.base64EncodedString().write(to: masterKeyURL, atomically: true, encoding: .utf8)
        try restrictPermissionsIfPossible(masterKeyURL)
        return key
    }

    private func restrictPermissionsIfPossible(_ url: URL) throws {
        #if os(macOS)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct EncryptedCredentialRecord: Codable, Sendable, Equatable {
    var version: Int
    var algorithm: String
    var serviceHash: String
    var accountHash: String
    var nonce: String
    var ciphertext: String
    var tag: String
}
