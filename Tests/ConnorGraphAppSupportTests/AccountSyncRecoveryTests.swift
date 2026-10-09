import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

@Suite("Account sync recovery", .serialized)
struct AccountSyncRecoveryTests {
    @Test @MainActor func offlineMessagesSurvivePullAndAreUploaded() async throws {
        let local = session("shared", messageID: "local", at: 2)
        let remote = session("shared", messageID: "remote", at: 1)
        let fixture = try await Fixture(remote: [change(remote)])
        defer { fixture.cleanUp() }
        _ = try fixture.sessions.saveSession(local)
        let result = try await fixture.coordinator().reconcile()
        #expect(result.failureMessage == nil)
        let pushed = try #require(await fixture.transport.pushedSessions.last)
        #expect(Set(pushed.messages.map(\.id)) == ["local", "remote"])
        let stored = try #require(try fixture.sessions.loadSession(id: "shared"))
        #expect(Set(stored.messages.map(\.id)) == ["local", "remote"])
    }

    @Test @MainActor func serverOnlySessionDoesNotEchoBack() async throws {
        let fixture = try await Fixture(remote: [change(session("remote-only", messageID: "m", at: 1))])
        defer { fixture.cleanUp() }
        #expect(try await fixture.coordinator().reconcile().failureMessage == nil)
        #expect(try fixture.sessions.loadSession(id: "remote-only") != nil)
        #expect(await fixture.transport.pushedSessions.isEmpty)
    }

    @Test @MainActor func millisecondDatesAndMessageOrderDoNotCreateAnEcho() async throws {
        var remote = session("fractional", messageID: "z", at: 1.1)
        remote.messages.append(AgentMessage(id: "a", role: .assistant, content: "reply", createdAt: Date(timeIntervalSince1970: 1.2)))
        remote.updatedAt = Date(timeIntervalSince1970: 1.2)
        let fixture = try await Fixture(remote: [change(remote)])
        defer { fixture.cleanUp() }
        #expect(try await fixture.coordinator().reconcile().failureMessage == nil)
        #expect(await fixture.transport.pushedSessions.isEmpty)
    }

    @Test @MainActor func failedDecryptionIsRetriedAfterRestartWithoutNewServerChanges() async throws {
        let otherKey = Data(repeating: 8, count: 32)
        let cipher = try AccountSyncPayloadCipher(keyData: otherKey)
        var failed = try change(session("deferred", messageID: "m", at: 1))
        let originalCipher = try AccountSyncPayloadCipher(keyData: Data(repeating: 7, count: 32))
        let clear = try originalCipher.decrypt(failed.payload, collection: failed.collection, recordID: failed.recordId).payload
        failed.payload = try cipher.encrypt(clear, collection: failed.collection, recordID: failed.recordId)
        let fixture = try await Fixture(remote: [failed, change(session("healthy", messageID: "h", at: 1))])
        defer { fixture.cleanUp() }
        let first = try await fixture.coordinator().reconcile()
        #expect(first.failureMessage != nil)
        #expect(try fixture.sessions.loadSession(id: "healthy") != nil)
        #expect(try fixture.sessions.loadSession(id: "deferred") == nil)
        try fixture.credentials.saveSyncKey(otherKey, userID: "1")
        let second = try await fixture.coordinator().reconcile()
        #expect(second.failureMessage == nil)
        #expect(try fixture.sessions.loadSession(id: "deferred") != nil)
        #expect(await fixture.transport.snapshotRequests == 1)
    }

    @Test @MainActor func rejectedUploadRemainsPendingWithoutAnotherLocalChange() async throws {
        let fixture = try await Fixture(remote: [], rejectSessionOnce: true)
        defer { fixture.cleanUp() }
        _ = try fixture.sessions.saveSession(session("unsent", messageID: "m", at: 1))
        #expect(try await fixture.coordinator().reconcile().failureMessage != nil)
        #expect(try await fixture.coordinator().reconcile().failureMessage == nil)
        #expect(await fixture.transport.sessionUploadAttempts == 2)
    }

    @Test @MainActor func snapshotRepairsRecordsSkippedByAnOldCursor() async throws {
        let fixture = try await Fixture(remote: [change(session("missed", messageID: "m", at: 1))])
        defer { fixture.cleanUp() }
        fixture.defaults.set(Data(#"{"cursor":77,"records":{}}"#.utf8), forKey: "ConnorAccountSyncState.1")
        #expect(try await fixture.coordinator().reconcile().failureMessage == nil)
        #expect(try fixture.sessions.loadSession(id: "missed") != nil)
    }

    @Test @MainActor func pendingDeletionIsNotRevivedByAnOlderRemoteSession() async throws {
        let original = session("deleted", messageID: "m", at: 1)
        let fixture = try await Fixture(remote: [change(original)])
        defer { fixture.cleanUp() }
        _ = try fixture.sessions.saveSession(original)
        try fixture.sessions.deleteSession(sessionID: original.id)
        #expect(try await fixture.coordinator().reconcile().failureMessage == nil)
        #expect(try fixture.sessions.loadSession(id: original.id)?.governance.deletedAt != nil)
        #expect(await fixture.transport.pushedSessionDeletes == [original.id])
    }

    @Test @MainActor func encryptedRemoteDeletionIsApplied() async throws {
        let original = session("remote-deleted", messageID: "m", at: 1)
        let cipher = try AccountSyncPayloadCipher(keyData: Data(repeating: 7, count: 32))
        var deletion = try ConnorSyncChange(collection: "sessions", recordId: original.id,
            payload: cipher.encrypt(.object(["updatedAt": .number(2_000)]), collection: "sessions", recordID: original.id), deleted: true)
        deletion.version = 2; deletion.sourceDeviceId = "peer"; deletion.cursor = 77
        let fixture = try await Fixture(remote: [deletion])
        defer { fixture.cleanUp() }
        _ = try fixture.sessions.saveSession(original)
        #expect(try await fixture.coordinator().reconcile().failureMessage == nil)
        #expect(try fixture.sessions.loadSession(id: original.id)?.governance.deletedAt != nil)
        #expect(await fixture.transport.pushedSessions.isEmpty)
    }

    private func session(_ id: String, messageID: String, at: Double) -> AgentSession {
        let date = Date(timeIntervalSince1970: at)
        return AgentSession(id: id, title: id, messages: [AgentMessage(id: messageID, role: .user, content: messageID, createdAt: date)], createdAt: Date(timeIntervalSince1970: 0), updatedAt: date)
    }

    private func change(_ session: AgentSession) throws -> ConnorSyncChange {
        let payload = try JSONDecoder().decode(ConnorJSONValue.self, from: JSONEncoder().encode(ConnorPortableSession(session)))
        let cipher = try AccountSyncPayloadCipher(keyData: Data(repeating: 7, count: 32))
        var change = try ConnorSyncChange(collection: "sessions", recordId: session.id, payload: cipher.encrypt(payload, collection: "sessions", recordID: session.id))
        change.version = 1; change.sourceDeviceId = "peer"; change.cursor = 77
        return change
    }
}

@MainActor private final class Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("SyncRecovery-\(UUID())")
    let suite = "SyncRecovery-\(UUID())"
    let defaults: UserDefaults
    let sessions: AppChatSessionRepository
    let credentials: AppConnorAccountCredentialStore
    let identity: AppUserIdentityStore
    let transport: RecoveryTransport

    init(remote: [ConnorSyncChange], rejectSessionOnce: Bool = false) async throws {
        defaults = UserDefaults(suiteName: suite)!
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try SQLiteGraphKernelStore(path: root.appendingPathComponent("graph.sqlite").path)
        try store.migrate()
        sessions = AppChatSessionRepository(store: store)
        credentials = AppConnorAccountCredentialStore(store: LocalEncryptedCredentialStore(rootDirectory: root.appendingPathComponent("credentials")))
        try credentials.saveTokens(.init(accessToken: "access", refreshToken: "refresh"))
        try credentials.saveSyncKey(Data(repeating: 7, count: 32), userID: "1")
        transport = RecoveryTransport(remote: remote, rejectSessionOnce: rejectSessionOnce)
        identity = AppUserIdentityStore(baseURL: URL(string: "http://127.0.0.1:1/")!, credentials: credentials, transport: transport, networkIsAvailable: { false }, syncDefaults: defaults)
        await identity.restoreSession()
    }
    func coordinator() -> AppAccountDataSyncCoordinator {
        AppAccountDataSyncCoordinator(sessions: sessions, settings: AppRuntimeSettingsRepository(configDirectory: root.appendingPathComponent("config")), memory: nil, identity: identity, defaults: UserDefaults(suiteName: suite)!)
    }
    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private actor RecoveryTransport: ConnorBackendHTTPTransport {
    let remote: [ConnorSyncChange]
    var rejectSessionOnce: Bool
    var snapshotRequests = 0
    var pushedSessions: [ConnorPortableSession] = []
    var pushedSessionDeletes: [String] = []
    var sessionUploadAttempts = 0
    init(remote: [ConnorSyncChange], rejectSessionOnce: Bool) { self.remote = remote; self.rejectSessionOnce = rejectSessionOnce }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url!.path
        var payload: [String: Any] = [:]
        if path.hasSuffix("/users/auth/me") {
            payload = ["id": 1, "username": "test", "email": "test@example.com", "role": "user", "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z"]
        } else if path.hasSuffix("/devices/heartbeat") {
            payload = ["deviceId": "test", "platform": "macos", "name": "test", "appVersion": "1", "lastSeenAt": "2026-01-01T00:00:00Z"]
        } else if path.hasSuffix("/snapshot") {
            snapshotRequests += 1
            payload = ["changes": try JSONSerialization.jsonObject(with: JSONEncoder().encode(remote)), "nextRecordId": remote.count, "cursor": 77, "hasMore": false]
        } else if path.hasSuffix("/pull") {
            payload = ["changes": [], "nextCursor": 77, "hasMore": false]
        } else if path.hasSuffix("/push") {
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let changes = try JSONDecoder().decode([ConnorSyncChange].self, from: JSONSerialization.data(withJSONObject: body["changes"]!))
            let cipher = try AccountSyncPayloadCipher(keyData: Data(repeating: 7, count: 32))
            var results: [[String: Any]] = []
            for change in changes {
                var applied = true
                if change.collection == "sessions" {
                    sessionUploadAttempts += 1
                    if rejectSessionOnce { applied = false; rejectSessionOnce = false }
                    else if change.deleted { pushedSessionDeletes.append(change.recordId) }
                    else {
                        let clear = try cipher.decrypt(change.payload, collection: change.collection, recordID: change.recordId)
                        pushedSessions.append(try JSONDecoder().decode(ConnorPortableSession.self, from: JSONEncoder().encode(clear.payload)))
                    }
                }
                results.append(["mutationId": change.mutationId!, "applied": applied, "cursor": 78, "version": 10])
            }
            // Receipts need not be in request order.
            payload = ["results": Array(results.reversed())]
        } else {
            payload = ["items": [], "total": 0, "page": 1, "pageSize": 100]
        }
        return (try JSONSerialization.data(withJSONObject: ["code": 0, "data": payload]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
