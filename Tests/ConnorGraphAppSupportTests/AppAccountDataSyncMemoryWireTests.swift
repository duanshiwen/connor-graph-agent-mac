import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Account Sync Memory Wire")
struct AppAccountDataSyncMemoryWireTests {
    @Test func l2StatementWireAlwaysEmitsOptionalFieldsAsNull() throws {
        let statement = MemoryOSStatement(
            id: "s1",
            subjectID: "e1",
            predicate: "knows",
            objectID: nil,
            text: "hello",
            committedAt: Date(timeIntervalSince1970: 0)
        )
        let wire = SyncMemoryL2Statement(statement)
        let data = try JSONEncoder().encode(wire)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"objectId\":null"))
        #expect(json.contains("\"sourceArtifactId\":null"))
    }

    @Test func l4RelationWireAlwaysEmitsOptionalFieldsAsNull() throws {
        let relation = MemoryOSEntityStatement(
            id: "r1",
            entityID: "e1",
            predicate: .relatedTo,
            objectEntityID: nil,
            text: "",
            committedAt: Date(timeIntervalSince1970: 0)
        )
        let wire = SyncMemoryL4Relation(relation)
        let data = try JSONEncoder().encode(wire)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"objectId\":null"))
        #expect(json.contains("\"sourceArtifactId\":null"))
    }

    @Test func l2StatementWireDecodesPayloadMissingOptionalFields() throws {
        let json = """
        {"id":"s1","subjectId":"e1","predicate":"knows","text":"hello",
         "factType":"other","assertionKind":"observed","confidence":0.5,
         "committedAt":"2026-08-05T00:00:00Z","evidenceSpanIdsJson":"[]",
         "metadataJson":"{}"}
        """
        let wire = try JSONDecoder().decode(SyncMemoryL2Statement.self, from: Data(json.utf8))
        #expect(wire.objectId == nil)
        #expect(wire.sourceArtifactId == nil)
        #expect(wire.makeStatement().text == "hello")
    }

    @Test func l1CaptureWireAlwaysEmitsRetrievalTextAsNull() throws {
        let event = MemoryOSCaptureEvent(
            id: "c1",
            provenanceObjectID: "p1",
            eventType: "user",
            occurredAt: Date(timeIntervalSince1970: 0),
            retrievalText: nil
        )
        let wire = SyncL1Capture(event: event)
        let data = try JSONEncoder().encode(wire)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"retrievalText\":null"))
    }

    @Test func l0ProvenanceWireAlwaysEmitsRequiredFields() throws {
        let provenance = MemoryOSProvenanceObject(
            id: "p1",
            sourceType: .manual,
            sourceID: nil,
            title: "t",
            content: "c",
            contentHash: "h",
            occurredAt: Date(timeIntervalSince1970: 0),
            sessionID: nil,
            workObjectID: nil
        )
        let wire = SyncL0Provenance(provenance: provenance)
        let data = try JSONEncoder().encode(wire)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"sourceId\":\"\""))
        #expect(json.contains("\"sessionId\":null"))
        #expect(json.contains("\"workObjectId\":null"))
    }

    @Test func l0SpanWireAlwaysEmitsOffsetFields() throws {
        let span = MemoryOSProvenanceSpan(
            id: "sp1",
            provenanceObjectID: "p1",
            startOffset: nil,
            endOffset: nil,
            text: "hello"
        )
        let wire = SyncL0Span(span: span)
        let data = try JSONEncoder().encode(wire)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"startOffset\":0"))
        #expect(json.contains("\"endOffset\":0"))
    }
}

extension AppAccountDataSyncMemoryWireTests {
    @Test func preferenceClockIgnoresDeviceSettingsAndAllowsClearingSharedFields() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppRuntimeSettingsRepository(configDirectory: root)
        var settings = try repository.loadOrCreateDefault()
        settings.preferences.city = "Shanghai"
        settings.preferences.country = "CN"
        try repository.save(settings)
        settings = try repository.loadOrCreateDefault()
        let stamp = settings.userPreferencesUpdatedAt
        #expect(stamp > 0)
        settings.updatedAt = Date(timeIntervalSinceNow: 5000)
        try repository.save(settings)
        #expect(try repository.loadOrCreateDefault().userPreferencesUpdatedAt == stamp)
        let cleared = SyncUserPreferences(AgentRuntimePreferenceSettings(), updatedAtMillis: stamp + 1000)
        let applied = cleared.applying(to: settings.preferences)
        #expect(applied.city.isEmpty && applied.country.isEmpty)
        settings.preferences = applied
        settings.userPreferencesUpdatedAt = stamp + 1000
        try repository.saveSynced(settings)
        #expect(try repository.loadOrCreateDefault().userPreferencesUpdatedAt == stamp + 1000)
    }
}

extension AppAccountDataSyncMemoryWireTests {
    @Test func mailboxWireDoesNotExportVaultIndexAsServerUsername() throws {
        let url = try #require(Bundle.module.url(forResource: "account-sync-config-v1", withExtension: "json", subdirectory: "SessionSync"))
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let wire = try JSONDecoder().decode(SyncMailAccount.self, from: JSONSerialization.data(withJSONObject: fixture["mail"]!))
        var local = SyncMailAccount.makeAccount(wire, local: nil)
        local.credentialBinding = AppMailCredentialStore.binding(accountID: local.id, email: "private-vault-index", authMode: .password)
        let received = SyncMailAccount.makeAccount(wire, local: local)
        #expect(received.credentialBinding == local.credentialBinding)
        #expect(received.loginUsername == "custom-login")
        #expect(SyncMailAccount(received) == wire)
        let encoded = try JSONEncoder().encode(received)
        #expect(try JSONDecoder().decode(MailAccount.self, from: encoded).loginUsername == "custom-login")
    }
}

extension AppAccountDataSyncMemoryWireTests {
    @Test func sharedSkillKeepsWireIdentityMetadataAndRemoteDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let store = SkillSyncStore(storagePaths: paths)
        let url = try #require(Bundle.module.url(forResource: "account-sync-config-v1", withExtension: "json", subdirectory: "SessionSync"))
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let wire = try JSONDecoder().decode(SyncSkillPack.self, from: JSONSerialization.data(withJSONObject: fixture["skill"]!))
        try store.apply(wire)
        let received = try #require(try store.pack(id: wire.id))
        #expect(received.id == wire.id && received.templatesJson == wire.templatesJson)
        #expect(received.category == wire.category && received.instructionsJson == wire.instructionsJson)
        #expect(received.updatedAt == wire.updatedAt && received.enabled == wire.enabled)
        try store.delete(id: wire.id)
        #expect(try store.pack(id: wire.id) == nil)
        let deletions = AccountSyncLocalDeletions(directory: paths.configDirectory)
        try deletions.record(collection: "skills", id: wire.id)
        #expect(try AccountSyncLocalDeletions(directory: paths.configDirectory).pending()["skills|\(wire.id)"] != nil)
        try deletions.clear("skills|\(wire.id)")
        #expect(try deletions.pending().isEmpty)
    }

    @Test func mailboxDeletionSurvivesStoreRestartAndRemoteDeleteDoesNotEcho() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try #require(Bundle.module.url(forResource: "account-sync-config-v1", withExtension: "json", subdirectory: "SessionSync"))
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let wire = try JSONDecoder().decode(SyncMailAccount.self, from: JSONSerialization.data(withJSONObject: fixture["mail"]!))
        let databaseURL = root.appendingPathComponent("mail.sqlite")
        let store = try SQLiteMailSourceStore(databaseURL: databaseURL)
        let account = SyncMailAccount.makeAccount(wire, local: nil)
        try await store.saveAccount(account)
        try await store.deleteAccount(id: account.id)
        let restarted = try SQLiteMailSourceStore(databaseURL: databaseURL)
        #expect(try await restarted.pendingAccountDeletions()[wire.id] != nil)
        try await restarted.clearAccountDeletion(id: account.id)
        try await restarted.saveAccount(account)
        try await restarted.applyRemoteAccountDelete(id: account.id)
        #expect(try await restarted.pendingAccountDeletions().isEmpty)
    }
}
