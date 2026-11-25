import Foundation
import SQLite3
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

struct IncrementalMailFixture {
    let root: URL
    let databaseURL: URL
    let store: SQLiteMailSourceStore
    var account: MailAccount
    var mailbox: MailMailbox

    init(count: Int = 1) async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("IncrementalMail-\(UUID())")
        databaseURL = root.appendingPathComponent("mail.sqlite")
        store = try SQLiteMailSourceStore(databaseURL: databaseURL)
        let accountID = MailAccountID(rawValue: "owner@example.test")
        account = MailAccount(id: accountID, provider: .genericIMAPSMTP, displayName: "Test", identities: [MailIdentity(id: MailIdentityID(rawValue: "owner"), displayName: "Test", address: MailAddress(email: "owner@example.test"))])
        let remote = RemoteIMAPMailbox(name: "Inbox", path: "INBOX", role: .inbox)
        mailbox = MailMailbox(id: remote.mailboxID(accountID: accountID), accountID: accountID, name: "Inbox", path: "INBOX", role: .inbox, status: MailMailboxStatus(syncCursor: MailSyncCursor(value: "1", uidValidity: "123")))
        try await store.saveAccount(account)
        try await store.saveMailbox(mailbox)
        if count > 0 {
            try await store.saveMessagesBatch((1...count).map { index in
                MailMessageDetail(summary: MailMessageSummary(id: remote.messageID(accountID: accountID, uid: String(index)), accountID: accountID, mailboxID: mailbox.id, subject: "Message \(index)", from: MailAddress(email: "sender@example.test"), to: [MailAddress(email: "owner@example.test")], date: Date(timeIntervalSince1970: Double(index)), snippet: "Body"), body: MailMessageBody(plainText: MailBodyPart(mimeType: "text/plain", text: "Body \(index)", byteCount: 6), redactedPreview: "Body \(index)"))
            })
        }
    }
    var shared: SharedMailStore { SharedMailStore(configDirectory: root.appendingPathComponent("config")) }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Incremental mail synchronization")
struct MailIncrementalSyncTests {
    @Test func thousandMessagesBecomeZeroWorkUntilOneChanges() async throws {
        let f = try await IncrementalMailFixture(count: 1000)
        defer { f.cleanUp() }
        let coldStart = ContinuousClock.now
        #expect(try await f.shared.capture(from: f.store) == 1000)
        let cold = coldStart.duration(to: .now)
        let baseline = try f.shared.syncSnapshot(storeID: nil, after: nil)
        #expect(baseline.messageIDs.count == 1000)
        let warmStart = ContinuousClock.now
        #expect(try await f.shared.capture(from: f.store) == 0)
        let warm = warmStart.duration(to: .now)
        #expect(try f.shared.syncSnapshot(storeID: baseline.storeID, after: baseline.revision).messageIDs.isEmpty)
        let id = try #require(await f.store.allMessageIDs().first)
        let message = try #require(await f.store.message(id: id))
        try await f.store.saveMessage(message) // identical poll result must stay clean
        #expect(try await f.shared.capture(from: f.store) == 0)
        try await f.store.updateFlags(messageIDs: [id]) { value in var value = value; value.isRead.toggle(); return value }
        #expect(try await f.shared.capture(from: f.store) == 1)
        let changed = try f.shared.syncSnapshot(storeID: baseline.storeID, after: baseline.revision)
        #expect(changed.messageIDs.count == 1)
        #expect(try f.shared.changedMessages(changed).first?.isRead == true)
        print("MAIL_SYNC_BENCH records=1000 cold=\(cold) unchanged=\(warm) unchanged_decoded=0 single_change_decoded=1")
    }

    @Test func durableCheckpointSurvivesReopenAndTracksOtherConnections() async throws {
        let f = try await IncrementalMailFixture(count: 2)
        defer { f.cleanUp() }
        _ = try await f.shared.capture(from: f.store)
        let snapshot = try f.store.syncSnapshot(storeID: nil, after: nil)
        let reopened = try SQLiteMailSourceStore(databaseURL: f.databaseURL)
        #expect(try await f.shared.capture(from: reopened) == 0)
        let id = try #require(await reopened.allMessageIDs().first)
        try await reopened.updateFlags(messageIDs: [id]) { value in var value = value; value.isRead.toggle(); return value }
        #expect(try f.store.syncSnapshot(storeID: snapshot.storeID, after: snapshot.revision).messageIDs == [id.rawValue])
        #expect(try await f.shared.capture(from: f.store) == 1)
        let journal = try SQLiteMailSourceStore(databaseURL: f.shared.directory.appendingPathComponent("sync-index.sqlite"))
        #expect(try journal.importedRevision(sourceID: snapshot.storeID) != nil)
    }

    @Test func healthUpdatesStayCleanAndIdentityChangesInvalidateMessages() async throws {
        var f = try await IncrementalMailFixture()
        defer { f.cleanUp() }
        _ = try await f.shared.capture(from: f.store)
        f.mailbox.status.lastSyncedAt = Date()
        f.mailbox.status.messageCount = 10
        try await f.store.saveMailbox(f.mailbox)
        #expect(try await f.shared.capture(from: f.store) == 0)
        f.mailbox.status.syncCursor?.uidValidity = "124"
        try await f.store.saveMailbox(f.mailbox)
        #expect(try await f.shared.capture(from: f.store) == 1)
        #expect(try f.shared.all().count == 2)
        #expect(try f.shared.visible().count == 1)
        #expect(try f.shared.visible().first?.uidValidity == "124")
        let beforeRoleChange = try f.store.syncSnapshot(storeID: nil, after: nil)
        f.mailbox.role = .sent
        try await f.store.saveMailbox(f.mailbox)
        #expect(try f.store.syncSnapshot(storeID: beforeRoleChange.storeID, after: beforeRoleChange.revision).messageIDs.count == 1)
    }

    @Test func failedCaptureDoesNotAcknowledgeSourceAndLegacyFilesAreSeeded() async throws {
        let f = try await IncrementalMailFixture()
        defer { f.cleanUp() }
        let id = SharedMailStore.recordID(address: "owner@example.test", folder: "INBOX", validity: "123", uid: "1")
        let blocked = f.shared.directory.appendingPathComponent(id + ".json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        var failed = false
        do { _ = try await f.shared.capture(from: f.store) } catch { failed = true }
        #expect(failed)
        try FileManager.default.removeItem(at: blocked)
        #expect(try await f.shared.capture(from: f.store) == 1)
        #expect(try await f.shared.capture(from: f.store) == 0)
        let baseline = try f.shared.syncSnapshot(storeID: nil, after: nil)
        #expect(try f.shared.syncSnapshot(storeID: "different-store", after: baseline.revision).messageIDs == [id])
        let legacy = SharedMailStore(configDirectory: f.root.appendingPathComponent("legacy"))
        try FileManager.default.createDirectory(at: legacy.directory, withIntermediateDirectories: true)
        let message = try #require(f.shared.all().first)
        try JSONEncoder().encode(message).write(to: legacy.directory.appendingPathComponent(message.id + ".json"))
        #expect(try legacy.syncSnapshot(storeID: nil, after: nil).messageIDs == [message.id])
    }

    @Test func rolledBackSourceChangesNeverEscapeTheJournal() async throws {
        let f = try await IncrementalMailFixture()
        defer { f.cleanUp() }
        let baseline = try f.store.syncSnapshot(storeID: nil, after: nil)
        var db: OpaquePointer?
        #expect(sqlite3_open(f.databaseURL.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "BEGIN; UPDATE mail_messages SET is_read=1; ROLLBACK;", nil, nil, nil) == SQLITE_OK)
        let after = try f.store.syncSnapshot(storeID: baseline.storeID, after: baseline.revision)
        #expect(after.revision == baseline.revision)
        #expect(after.messageIDs.isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CONNOR_MAIL_BENCHMARK_DB"] != nil))
    func copiedLocalMailboxBenchmark() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["CONNOR_MAIL_BENCHMARK_DB"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MailBenchmark-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteMailSourceStore(databaseURL: URL(fileURLWithPath: path))
        let shared = SharedMailStore(configDirectory: root)
        let started = ContinuousClock.now
        let coldCount = try await shared.capture(from: store)
        let cold = started.duration(to: .now)
        let baseline = try shared.syncSnapshot(storeID: nil, after: nil)
        let warmStart = ContinuousClock.now
        let warmCount = try await shared.capture(from: store)
        let changes = try shared.syncSnapshot(storeID: baseline.storeID, after: baseline.revision)
        let warm = warmStart.duration(to: .now)
        #expect(warmCount == 0 && changes.messageIDs.isEmpty)
        print("LOCAL_MAIL_BENCHMARK captured=\(coldCount) cold=\(cold) unchanged=\(warm) unchanged_decoded=\(warmCount)")
    }
}
