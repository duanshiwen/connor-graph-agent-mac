import CryptoKit
import Foundation

public enum AccountSyncCryptoError: Error, LocalizedError, Sendable, Equatable {
    case invalidKey
    case invalidEnvelope
    case unsupportedEnvelope
    case authenticationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidKey: "同步加密密钥无效，请重新登录。"
        case .invalidEnvelope: "同步数据的加密格式无效。"
        case .unsupportedEnvelope: "同步数据使用了当前客户端不支持的加密版本。"
        case .authenticationFailed: "无法解密同步数据，请确认两端使用同一账号密码。"
        }
    }
}

/// Cross-platform account-sync payload protocol shared with Android.
public struct AccountSyncPayloadCipher: Sendable {
    public static let iterations = 210_000
    private static let marker = "_connorE2EE"
    private let key: SymmetricKey
    private let nonceGenerator: @Sendable () throws -> Data

    public init(keyData: Data, nonceGenerator: @escaping @Sendable () throws -> Data = {
        var bytes = [UInt8](repeating: 0, count: 12)
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes)
    }) throws {
        guard keyData.count == 32 else { throw AccountSyncCryptoError.invalidKey }
        key = SymmetricKey(data: keyData)
        self.nonceGenerator = nonceGenerator
    }

    public static func deriveKey(password: String, userID: String, iterations: Int = Self.iterations) -> Data {
        let passwordData = Data(password.utf8)
        let salt = Data("connor-sync-e2ee-v1:\(userID)".utf8)
        var block = salt
        block.append(contentsOf: [0, 0, 0, 1])
        var u = Data(HMAC<SHA256>.authenticationCode(for: block, using: SymmetricKey(data: passwordData)))
        var result = u
        if iterations > 1 {
            for _ in 1..<iterations {
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: SymmetricKey(data: passwordData)))
                for index in result.indices { result[index] ^= u[index] }
            }
        }
        return result
    }

    public func encrypt(_ payload: ConnorJSONValue, collection: String, recordID: String) throws -> ConnorJSONValue {
        let plaintext = try Self.encoder.encode(payload)
        let nonceData = try nonceGenerator()
        guard nonceData.count == 12 else { throw AccountSyncCryptoError.invalidEnvelope }
        let sealed = try AES.GCM.seal(
            plaintext,
            using: key,
            nonce: try AES.GCM.Nonce(data: nonceData),
            authenticating: Self.aad(collection: collection, recordID: recordID)
        )
        var ciphertext = sealed.ciphertext
        ciphertext.append(sealed.tag)
        return .object([
            Self.marker: .object([
                "v": .number(1),
                "alg": .string("A256GCM"),
                "nonce": .string(nonceData.base64EncodedString()),
                "ciphertext": .string(ciphertext.base64EncodedString()),
            ]),
        ])
    }

    public func decrypt(_ payload: ConnorJSONValue, collection: String, recordID: String) throws -> (payload: ConnorJSONValue, encrypted: Bool) {
        guard case .object(let root) = payload, let wrapped = root[Self.marker] else { return (payload, false) }
        guard case .object(let envelope) = wrapped,
              envelope["v"] == .number(1), envelope["alg"] == .string("A256GCM"),
              case .string(let nonceString) = envelope["nonce"],
              case .string(let ciphertextString) = envelope["ciphertext"],
              let nonceData = Data(base64Encoded: nonceString), nonceData.count == 12,
              let combined = Data(base64Encoded: ciphertextString), combined.count >= 16 else {
            throw AccountSyncCryptoError.invalidEnvelope
        }
        let ciphertext = combined.dropLast(16)
        let tag = combined.suffix(16)
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonceData), ciphertext: ciphertext, tag: tag)
            let plaintext = try AES.GCM.open(box, using: key, authenticating: Self.aad(collection: collection, recordID: recordID))
            return (try Self.decoder.decode(ConnorJSONValue.self, from: plaintext), true)
        } catch let error as AccountSyncCryptoError {
            throw error
        } catch {
            throw AccountSyncCryptoError.authenticationFailed
        }
    }

    private static func aad(collection: String, recordID: String) -> Data {
        Data("connor-sync-e2ee-v1\0\(collection)\0\(recordID)".utf8)
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder(); value.outputFormatting = [.sortedKeys]; return value
    }()
    private static let decoder = JSONDecoder()
}
