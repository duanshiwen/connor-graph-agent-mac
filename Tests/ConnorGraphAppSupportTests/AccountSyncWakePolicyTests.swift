import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Event driven account sync")
struct AccountSyncWakePolicyTests {
    @Test func idleWatermarksNeverRequestADataPass() {
        for _ in 0..<100 {
            #expect(!AccountSyncWakePolicy.needsSync(remoteCursor: 42, durableCursor: 42, localChanged: false))
        }
    }
    @Test func localEditsLostPushesStartupAndOldServersStillRequestSync() {
        #expect(AccountSyncWakePolicy.needsSync(remoteCursor: 42, durableCursor: 42, localChanged: true))
        #expect(AccountSyncWakePolicy.needsSync(remoteCursor: 43, durableCursor: 42, localChanged: false))
        #expect(AccountSyncWakePolicy.needsSync(remoteCursor: 0, durableCursor: nil, localChanged: false))
        #expect(AccountSyncWakePolicy.needsSync(remoteCursor: nil, durableCursor: 42, localChanged: false))
    }
    @Test func heartbeatCapabilityDistinguishesZeroFromAnOldServer() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let base = #"{"deviceId":"d","platform":"macos","name":"test","appVersion":"1","lastSeenAt":"2026-01-01T00:00:00Z"}"#
        #expect(try decoder.decode(ConnorSyncDevice.self, from: Data(base.utf8)).syncCursor == nil)
        let zero = String(base.dropLast()) + #","syncCursor":0}"#
        #expect(try decoder.decode(ConnorSyncDevice.self, from: Data(zero.utf8)).syncCursor == 0)
    }
}
