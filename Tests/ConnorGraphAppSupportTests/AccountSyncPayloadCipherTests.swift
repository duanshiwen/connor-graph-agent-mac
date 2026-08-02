import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Account Sync Payload Cipher")
struct AccountSyncPayloadCipherTests {
    @Test func matchesAndroidProtocolVectorAndBindsRecordIdentity() throws {
        let key = AccountSyncPayloadCipher.deriveKey(password: "correct horse battery staple", userID: "42", iterations: 2)
        #expect(key.base64EncodedString() == "kF+5v5+K+DoXoqLCj3c7rHcYVZsrpBJVurXH3/xuEFw=")
        let cipher = try AccountSyncPayloadCipher(keyData: key, nonceGenerator: { Data(0..<12) })
        let payload: ConnorJSONValue = .object(["title": .string("hello"), "count": .number(3)])
        let encrypted = try cipher.encrypt(payload, collection: "sessions", recordID: "abc")
        let clear = try cipher.decrypt(encrypted, collection: "sessions", recordID: "abc")
        #expect(clear.payload == payload)
        #expect(clear.encrypted)
        #expect(throws: AccountSyncCryptoError.authenticationFailed) {
            _ = try cipher.decrypt(encrypted, collection: "sessions", recordID: "other")
        }
    }

    @Test func recognizesLegacyPlaintextForMigration() throws {
        let cipher = try AccountSyncPayloadCipher(keyData: Data(repeating: 7, count: 32))
        let payload: ConnorJSONValue = .object(["legacy": .bool(true)])
        let clear = try cipher.decrypt(payload, collection: "settings", recordID: "profile")
        #expect(clear.payload == payload)
        #expect(!clear.encrypted)
    }
}
