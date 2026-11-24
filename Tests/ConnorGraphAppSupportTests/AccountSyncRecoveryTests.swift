import Foundation
import Combine
import CryptoKit
import Testing
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

@Suite("Account sync recovery", .serialized)
struct AccountSyncRecoveryTests {
    @Test(arguments: [true, false])
    @MainActor func reconnectReceivesCommittedChangesEvenAfterSenderLeaves(senderOnline: Bool) async throws {
        let original = session("shared", messageID: "original", at: 1)
        let removed = session("removed", messageID: "old", at: 1)
        let fixture = try await Fixture(remote: [change(original), change(removed)])
        defer { fixture.cleanUp() }
        #expect(try await fixture.coordinator().reconcile().failureMessage == nil)
        #expect(fixture.defaults.integer(forKey: "ConnorAccountSyncCursor.1") == 77)
        fixture.identity.onDeviceSyncPass = {
            let result = try await fixture.coordinator().reconcile()
            if let failure = result.failureMessage { throw NSError(domain: "Reconnect", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
        }
        fixture.identity.setDeviceSyncEnabled(true) // still offline
        var update = try change(session("shared", messageID: "offline-update", at: 2))
        update.version = 2; update.cursor = 78
        let cipher = try AccountSyncPayloadCipher(keyData: Data(repeating: 7, count: 32))
        var deletion = try ConnorSyncChange(collection: "sessions", recordId: "removed",
            payload: cipher.encrypt(.object(["updatedAt": .number(3_000)]), collection: "sessions", recordID: "removed"), deleted: true)
        deletion.version = 2; deletion.sourceDeviceId = "peer"; deletion.cursor = 79
        await fixture.transport.publishWhileReceiverOffline([update, deletion], senderOnline: senderOnline)
        // The availability transition is the production reconnect entry; no manual
        // sync, local edit, peer_online or sync_changed notification is supplied.
        fixture.connectivity.setOnline(true)
        do {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if fixture.defaults.integer(forKey: "ConnorAccountSyncCursor.1") == 79,
               case .upToDate = fixture.identity.deviceSyncStatus { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let received = try #require(try fixture.sessions.loadSession(id: "shared"))
        #expect(Set(received.messages.map(\.id)) == ["original", "offline-update"])
        #expect(try fixture.sessions.loadSession(id: "removed")?.governance.deletedAt != nil)
        #expect(fixture.defaults.integer(forKey: "ConnorAccountSyncCursor.1") == 79)
        #expect(await fixture.transport.incrementalRequests > 0)
        #expect(await fixture.transport.peerPresenceRequests == 0)
        } catch {
            await fixture.identity.logout()
            throw error
        }
        await fixture.identity.logout() // stop the live socket and lease tasks before removing the fixture
        fixture.connectivity.setOnline(false)
        fixture.identity.setDeviceSyncEnabled(false)
        await Task.yield()
    }

    @Test @MainActor func deletedKnowledgeRecordsDoNotDecodeTombstonesAsLiveMemory() async throws {
        let collections = ["memory_l2", "memory_l2_nodes", "memory_l3", "memory_l4_entities", "memory_l4_relations"]
        let cipher = try AccountSyncPayloadCipher(keyData: Data(repeating: 7, count: 32))
        let changes = try collections.enumerated().map { index, collection in
            var deletion = try ConnorSyncChange(collection: collection, recordId: "deleted-\(index)",
                payload: cipher.encrypt(.object(["updatedAt": .number(2_000)]), collection: collection, recordID: "deleted-\(index)"), deleted: true)
            deletion.version = 2; deletion.sourceDeviceId = "peer"; deletion.cursor = 77
            return deletion
        }
        let fixture = try await Fixture(remote: changes)
        defer { fixture.cleanUp() }
        let memory = try SQLiteMemoryOSStore(path: fixture.root.appendingPathComponent("memory.sqlite").path)
        try memory.migrate()
        try memory.execute("""
        INSERT INTO memory_l3_beliefs(id, statement, created_at, updated_at)
        VALUES ('deleted-2', 'must disappear', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');
        """)
        #expect(try await fixture.coordinator(memory: memory).reconcile().failureMessage == nil)
        #expect(try memory.query(sql: "SELECT COUNT(*) FROM memory_l3_beliefs WHERE id='deleted-2'") == [["0"]])
    }
    @Test @MainActor func receivedDialogueIsVisibleEvenWhenLocalUploadFails() async throws {
        let fixture = try await Fixture(remote: [change(session("remote", messageID: "remote-message", at: 2))], failPush: true)
        defer { fixture.cleanUp() }
        _ = try fixture.sessions.saveSession(session("local", messageID: "local-message", at: 1))
        let observation = ReceiveObservation()
        let coordinator = fixture.coordinator(onReceived: { result in await observation.record(result) })
        var uploadFailed = false
        do { _ = try await coordinator.reconcile() } catch { uploadFailed = true }
        #expect(uploadFailed)
        #expect(try fixture.sessions.loadSession(id: "local") != nil)
        #expect(try fixture.sessions.loadSession(id: "remote") != nil)
        #expect(observation.received.contains("remote"))
    }

    @Test @MainActor func portableNotesRetainTheirKindAndLegacyPayloadsDoNotDemoteExistingNotes() throws {
        var note = session("note", messageID: "body", at: 1)
        note.governance.kind = .note
        let wire = ConnorPortableSession(note)
        #expect(wire.kind == "note")
        #expect(wire.merging(into: nil).governance.kind == .note)
        var legacy = wire; legacy.kind = nil
        #expect(legacy.merging(into: note).governance.kind == .note)
    }

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

    @Test @MainActor func missingMailFragmentBehindCursorTriggersOneFreshSnapshot() async throws {
        var mail = SharedMailMessage()
        mail.mailboxAddress = "owner@example.test"
        mail.folder = "INBOX"
        mail.uidValidity = "42"
        mail.uid = "7"
        mail.id = SharedMailStore.recordID(address: mail.mailboxAddress, folder: mail.folder, validity: mail.uidValidity, uid: mail.uid)
        mail.bodyText = String(repeating: "正文😀", count: 75_000)
        mail.bodyAvailable = true
        mail.updatedAt = 100
        let records = try SessionChunks.project(id: mail.id, payload: SharedMailStore.wire(mail), mail: true)
        let cipher = try AccountSyncPayloadCipher(keyData: Data(repeating: 7, count: 32))
        func change(_ id: String, _ value: ConnorJSONValue) throws -> ConnorSyncChange {
            var result = try ConnorSyncChange(collection: "mail_messages", recordId: id,
                payload: cipher.encrypt(value, collection: "mail_messages", recordID: id))
            result.sourceDeviceId = "peer"
            result.version = 1
            return result
        }
        let manifest = try change(mail.id, #require(records[mail.id]))
        let parts = try records.filter { $0.key != mail.id }.map { try change($0.key, $0.value) }
        #expect(!parts.isEmpty)
        let fixture = try await Fixture(remote: [manifest] + parts)
        defer { fixture.cleanUp() }
        fixture.defaults.set(Data(#"{"cursor":77,"records":{},"repairVersion":4,"snapshotAfterID":100}"#.utf8), forKey: "ConnorAccountSyncState.1")
        await fixture.transport.queueIncremental([manifest] + Array(parts.dropFirst()))
        let first = try await fixture.coordinator().reconcile()
        #expect(first.failureMessage != nil)
        #expect(await fixture.transport.snapshotRequests == 0)
        let second = try await fixture.coordinator().reconcile()
        #expect(second.failureMessage == nil)
        #expect(second.pushedChangeCount == 0)
        let store = SharedMailStore(configDirectory: fixture.root.appendingPathComponent("config"))
        #expect(try store.get(mail.id)?.bodyText == mail.bodyText)
        #expect(await fixture.transport.snapshotAfterIDs == [0])
        _ = try await fixture.coordinator().reconcile()
        #expect(await fixture.transport.snapshotRequests == 1)
    }

    @Test @MainActor func incrementalMemorySkipsUnchangedRowsAndPreservesDeletes() async throws {
        let fixture = try await Fixture(remote: [])
        defer { fixture.cleanUp() }
        let memory = try SQLiteMemoryOSStore(path: fixture.root.appendingPathComponent("memory.sqlite").path)
        try memory.migrate()
        let date = Date(timeIntervalSince1970: 1_800)
        for id in ["keep", "update", "delete"] {
            try memory.upsert(provenance: MemoryOSProvenanceObject(id: id, sourceType: .manual, title: id, content: id, occurredAt: date))
        }
        let first = try await fixture.coordinator(memory: memory).reconcile()
        #expect(first.failureMessage == nil)
        // Poison an unchanged row's date. Incremental sync must not decode it.
        // Capture the watermark after this intentionally invalid local edit.
        try memory.execute("UPDATE memory_l0_provenance_objects SET occurred_at = 'invalid' WHERE id = 'keep';")
        let snapshot = try memory.accountSyncSnapshot(storeID: nil, after: nil)
        let key = "ConnorAccountSyncState.1"
        var state = try JSONSerialization.jsonObject(with: fixture.defaults.data(forKey: key)!) as! [String: Any]
        state["memoryRevision"] = snapshot.revision
        fixture.defaults.set(try JSONSerialization.data(withJSONObject: state), forKey: key)
        try memory.execute("UPDATE memory_l0_provenance_objects SET content = 'changed' WHERE id = 'update';")
        try memory.deleteProvenanceObject(id: "delete")
        let before = await fixture.transport.pushedMemoryChanges.count
        let second = try await fixture.coordinator(memory: memory).reconcile()
        #expect(second.failureMessage == nil)
        let changes = Array(await fixture.transport.pushedMemoryChanges.dropFirst(before))
        #expect(Set(changes.map(\.recordId)) == ["update", "delete"])
        #expect(changes.first { $0.recordId == "delete" }?.deleted == true)
        #expect(!changes.contains { $0.recordId == "keep" })
        #expect(try await fixture.coordinator(memory: memory).reconcile().pushedChangeCount == 0)
    }

    @Test @MainActor func failedMemoryUploadsDoNotAdvanceIncrementalWatermark() async throws {
        let fixture = try await Fixture(remote: [])
        defer { fixture.cleanUp() }
        let memory = try SQLiteMemoryOSStore(path: fixture.root.appendingPathComponent("memory.sqlite").path)
        try memory.migrate()
        try memory.upsert(provenance: MemoryOSProvenanceObject(id: "retry", sourceType: .manual, title: "retry", content: "first", occurredAt: Date()))
        _ = try await fixture.coordinator(memory: memory).reconcile()
        try memory.execute("UPDATE memory_l0_provenance_objects SET content = 'retry me' WHERE id = 'retry';")
        await fixture.transport.setFailPush(true)
        var failed = false
        do { _ = try await fixture.coordinator(memory: memory).reconcile() } catch { failed = true }
        #expect(failed)
        await fixture.transport.setFailPush(false)
        let retried = try await fixture.coordinator(memory: memory).reconcile()
        #expect(retried.failureMessage == nil)
        #expect(retried.pushedChangeCount == 1)
        #expect(try await fixture.coordinator(memory: memory).reconcile().pushedChangeCount == 0)
    }

    @Test @MainActor func memoryWrittenDuringUploadRemainsEligibleForNextPass() async throws {
        let fixture = try await Fixture(remote: [])
        defer { fixture.cleanUp() }
        let memory = try SQLiteMemoryOSStore(path: fixture.root.appendingPathComponent("memory.sqlite").path)
        try memory.migrate()
        try memory.upsert(provenance: MemoryOSProvenanceObject(id: "concurrent", sourceType: .manual, title: "concurrent", content: "first", occurredAt: Date()))
        _ = try await fixture.coordinator(memory: memory).reconcile()
        try memory.execute("UPDATE memory_l0_provenance_objects SET content = 'second' WHERE id = 'concurrent';")
        await fixture.transport.setOnPush {
            try memory.execute("UPDATE memory_l0_provenance_objects SET content = 'third' WHERE id = 'concurrent';")
        }
        #expect(try await fixture.coordinator(memory: memory).reconcile().pushedChangeCount == 1)
        #expect(try await fixture.coordinator(memory: memory).reconcile().pushedChangeCount == 1)
        #expect(try await fixture.coordinator(memory: memory).reconcile().pushedChangeCount == 0)
    }

    @Test @MainActor func payloadHashPreservesLegacyCanonicalization() async throws {
        let fixture = try await Fixture(remote: [])
        defer { fixture.cleanUp() }
        let coordinator = fixture.coordinator()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var portable = ConnorPortableSession(session("canonical", messageID: "message", at: 1.234))
        portable.labels = ["z", "a"]
        let payload = try decoder.decode(ConnorJSONValue.self, from: encoder.encode(portable))
        portable.labels.sort()
        portable.updatedAt = 1_000
        portable.messages[0].createdAt = 1_000
        let canonical = try decoder.decode(ConnorJSONValue.self, from: encoder.encode(portable))
        let samples: [(ConnorJSONValue, ConnorJSONValue)] = [
            (payload, canonical),
            (.object(["id": .string("memory"), "content": .string("中文内容")]), .object(["id": .string("memory"), "content": .string("中文内容")])),
            (.object(["updatedAt": .number(123)]), .object(["updatedAt": .number(123)])),
            (.array([.string("value"), .number(1)]), .array([.string("value"), .number(1)]))
        ]
        for (input, normalized) in samples {
            let expected = SHA256.hash(data: try encoder.encode(normalized)).map { String(format: "%02x", $0) }.joined()
            #expect(try await coordinator.payloadHash(input) == expected)
        }
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
    let connectivity: RecoveryConnectivity
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("SyncRecovery-\(UUID())")
    let suite = "SyncRecovery-\(UUID())"
    let defaults: UserDefaults
    let sessions: AppChatSessionRepository
    let credentials: AppConnorAccountCredentialStore
    let identity: AppUserIdentityStore
    let transport: RecoveryTransport

    init(remote: [ConnorSyncChange], rejectSessionOnce: Bool = false, failPush: Bool = false) async throws {
        let connectivity = RecoveryConnectivity()
        self.connectivity = connectivity
        defaults = UserDefaults(suiteName: suite)!
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try SQLiteGraphKernelStore(path: root.appendingPathComponent("graph.sqlite").path)
        try store.migrate()
        sessions = AppChatSessionRepository(store: store)
        credentials = AppConnorAccountCredentialStore(store: LocalEncryptedCredentialStore(rootDirectory: root.appendingPathComponent("credentials")))
        try credentials.saveTokens(.init(accessToken: "access", refreshToken: "refresh"))
        try credentials.saveSyncKey(Data(repeating: 7, count: 32), userID: "1")
        transport = RecoveryTransport(remote: remote, rejectSessionOnce: rejectSessionOnce, failPush: failPush)
        identity = AppUserIdentityStore(baseURL: URL(string: "http://127.0.0.1:1/")!, credentials: credentials, transport: transport, networkIsAvailable: { connectivity.online }, syncAvailability: connectivity.changes.eraseToAnyPublisher(), syncDefaults: defaults)
        await identity.restoreSession()
    }
    func coordinator(memory: SQLiteMemoryOSStore? = nil, onReceived: (@Sendable (AppAccountDataSyncResult) async -> Void)? = nil) -> AppAccountDataSyncCoordinator {
        AppAccountDataSyncCoordinator(sessions: sessions, settings: AppRuntimeSettingsRepository(configDirectory: root.appendingPathComponent("config")), memory: memory, identity: identity, defaults: UserDefaults(suiteName: suite)!, onReceived: onReceived)
    }
    func cleanUp() {
        connectivity.setOnline(false)
        identity.onDeviceSyncPass = nil
        identity.setDeviceSyncEnabled(false)
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor private final class RecoveryConnectivity {
    var online = false
    let changes = CurrentValueSubject<Bool, Never>(false)
    func setOnline(_ value: Bool) { online = value; changes.send(value) }
}

private actor RecoveryTransport: ConnorBackendHTTPTransport {
    let remote: [ConnorSyncChange]
    var rejectSessionOnce: Bool
    var failPush: Bool
    var onPush: (@Sendable () throws -> Void)?
    var snapshotRequests = 0
    var snapshotAfterIDs: [Int64] = []
    private var incremental: [ConnorSyncChange] = []
    private var cursor: Int64 = 77
    private var senderOnline = true
    var incrementalRequests = 0
    var peerPresenceRequests = 0
    func publishWhileReceiverOffline(_ changes: [ConnorSyncChange], senderOnline: Bool) {
        incremental = changes
        cursor = changes.compactMap(\.cursor).max() ?? cursor
        self.senderOnline = senderOnline
    }

    func queueIncremental(_ changes: [ConnorSyncChange]) { incremental = changes }
    var pushedSessions: [ConnorPortableSession] = []
    var pushedSessionDeletes: [String] = []
    var pushedMemoryChanges: [ConnorSyncChange] = []
    var sessionUploadAttempts = 0
    init(remote: [ConnorSyncChange], rejectSessionOnce: Bool, failPush: Bool = false) { self.remote = remote; self.rejectSessionOnce = rejectSessionOnce; self.failPush = failPush }

    func setFailPush(_ value: Bool) { failPush = value }
    func setOnPush(_ operation: @escaping @Sendable () throws -> Void) { onPush = operation }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url!.path
        var payload: [String: Any] = [:]
        if path.hasSuffix("/users/auth/me") {
            payload = ["id": 1, "username": "test", "email": "test@example.com", "role": "user", "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z"]
        } else if path.hasSuffix("/devices/heartbeat") {
            payload = ["deviceId": "test", "platform": "macos", "name": "test", "appVersion": "1", "lastSeenAt": "2026-01-01T00:00:00Z", "syncCursor": cursor]
        } else if path.hasSuffix("/snapshot") {
            snapshotRequests += 1
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            snapshotAfterIDs.append(Int64(query?.first { $0.name == "afterId" }?.value ?? "") ?? -1)
            payload = ["changes": try JSONSerialization.jsonObject(with: JSONEncoder().encode(remote)), "nextRecordId": remote.count, "cursor": 77, "hasMore": false]
        } else if path.hasSuffix("/pull") {
            incrementalRequests += 1
            payload = ["changes": try JSONSerialization.jsonObject(with: JSONEncoder().encode(incremental)), "nextCursor": cursor, "hasMore": false]
            incremental = []
        } else if path.hasSuffix("/devices") {
            peerPresenceRequests += 1
            payload = ["items": senderOnline ? [["deviceId": "peer"]] : []]
        } else if path.hasSuffix("/push") {
            if failPush { return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!) }
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let changes = try JSONDecoder().decode([ConnorSyncChange].self, from: JSONSerialization.data(withJSONObject: body["changes"]!))
            let cipher = try AccountSyncPayloadCipher(keyData: Data(repeating: 7, count: 32))
            var results: [[String: Any]] = []
            for change in changes {
                if change.collection.hasPrefix("memory_") { pushedMemoryChanges.append(change) }
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
            let operation = onPush
            onPush = nil
            try operation?()
            // Receipts need not be in request order.
            payload = ["results": Array(results.reversed())]
        } else {
            payload = ["items": [], "total": 0, "page": 1, "pageSize": 100]
        }
        return (try JSONSerialization.data(withJSONObject: ["code": 0, "data": payload]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor private final class ReceiveObservation {
    var received: Set<String> = []
    func record(_ result: AppAccountDataSyncResult) { received.formUnion(result.appliedSessionIDs) }
}
