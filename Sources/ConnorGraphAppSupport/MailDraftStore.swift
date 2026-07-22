import Foundation
import ConnorGraphCore

public struct MailRuntimeSendApproval: Codable, Sendable, Equatable {
    public var draftID: MailDraftID
    public var title: String
    public var from: String
    public var to: [String]
    public var cc: [String]
    public var bcc: [String]
    public var subject: String
    public var bodyPreview: String
    public var attachmentCount: Int
    public var riskSummary: String
    public var envelopeHash: String

    public init(draft: MailDraft, from: String) {
        self.draftID = draft.id
        self.title = "Send email authorization"
        self.from = from
        self.to = draft.to.map(\.email)
        self.cc = draft.cc.map(\.email)
        self.bcc = draft.bcc.map(\.email)
        self.subject = draft.subject
        self.bodyPreview = String(draft.body.prefix(500))
        self.attachmentCount = draft.attachmentIDs.count
        self.riskSummary = "Email sending follows the current session permission mode."
        self.envelopeHash = draft.envelopeHash()
    }
}

public protocol MailDraftRepository: Sendable {
    func save(_ draft: MailDraft) async throws
    func draft(id: MailDraftID) async throws -> MailDraft?
    func listDrafts(accountID: MailAccountID?, status: MailDraftStatus?) async throws -> [MailDraft]
    func updateStatus(id: MailDraftID, status: MailDraftStatus, lastSendError: String?, sentReceiptID: String?) async throws -> MailDraft
    func updateApprovedEnvelopeHash(id: MailDraftID, envelopeHash: String?) async throws -> MailDraft
    func discard(id: MailDraftID) async throws -> MailDraft
    func recordSendAttempt(_ attempt: MailSendAttempt) async throws
    func sendAttempts(draftID: MailDraftID) async throws -> [MailSendAttempt]
}

public extension MailDraftRepository {
    func listDrafts(accountID: MailAccountID? = nil, status: MailDraftStatus? = nil) async throws -> [MailDraft] {
        try await listDrafts(accountID: accountID, status: status)
    }

    func updateStatus(id: MailDraftID, status: MailDraftStatus, lastSendError: String? = nil, sentReceiptID: String? = nil) async throws -> MailDraft {
        try await updateStatus(id: id, status: status, lastSendError: lastSendError, sentReceiptID: sentReceiptID)
    }
}

public actor InMemoryMailDraftRepository: MailDraftRepository {
    private var drafts: [MailDraftID: MailDraft]
    private var attempts: [MailDraftID: [MailSendAttempt]]

    public init(drafts: [MailDraft] = [], attempts: [MailSendAttempt] = []) {
        self.drafts = Dictionary(uniqueKeysWithValues: drafts.map { ($0.id, $0) })
        self.attempts = Dictionary(grouping: attempts, by: \.draftID)
    }

    public func save(_ draft: MailDraft) async throws {
        drafts[draft.id] = draft
    }

    public func draft(id: MailDraftID) async throws -> MailDraft? {
        drafts[id]
    }

    public func listDrafts(accountID: MailAccountID?, status: MailDraftStatus?) async throws -> [MailDraft] {
        drafts.values
            .filter { accountID == nil || $0.accountID == accountID }
            .filter { status == nil || $0.status == status }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func updateStatus(id: MailDraftID, status: MailDraftStatus, lastSendError: String?, sentReceiptID: String?) async throws -> MailDraft {
        guard var draft = drafts[id] else { throw MailRuntimeError.draftNotFound(id.rawValue) }
        draft.status = status
        draft.lastSendError = lastSendError
        draft.sentReceiptID = sentReceiptID
        draft.updatedAt = Date()
        drafts[id] = draft
        return draft
    }

    public func updateApprovedEnvelopeHash(id: MailDraftID, envelopeHash: String?) async throws -> MailDraft {
        guard var draft = drafts[id] else { throw MailRuntimeError.draftNotFound(id.rawValue) }
        draft.approvedEnvelopeHash = envelopeHash
        draft.updatedAt = Date()
        drafts[id] = draft
        return draft
    }

    public func discard(id: MailDraftID) async throws -> MailDraft {
        try await updateStatus(id: id, status: .discarded)
    }

    public func recordSendAttempt(_ attempt: MailSendAttempt) async throws {
        attempts[attempt.draftID, default: []].append(attempt)
    }

    public func sendAttempts(draftID: MailDraftID) async throws -> [MailSendAttempt] {
        (attempts[draftID] ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}

public actor FileBackedMailDraftRepository: MailDraftRepository {
    public struct Snapshot: Codable, Sendable, Equatable {
        public var drafts: [MailDraft]
        public var attempts: [MailSendAttempt]

        public init(drafts: [MailDraft] = [], attempts: [MailSendAttempt] = []) {
            self.drafts = drafts
            self.attempts = attempts
        }
    }

    private let storeURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storeURL: URL) {
        self.storeURL = storeURL
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func save(_ draft: MailDraft) async throws {
        var snapshot = try loadSnapshot()
        snapshot.drafts.removeAll { $0.id == draft.id }
        snapshot.drafts.append(draft)
        try saveSnapshot(snapshot)
    }

    public func draft(id: MailDraftID) async throws -> MailDraft? {
        try loadSnapshot().drafts.first { $0.id == id }
    }

    public func listDrafts(accountID: MailAccountID?, status: MailDraftStatus?) async throws -> [MailDraft] {
        try loadSnapshot().drafts
            .filter { accountID == nil || $0.accountID == accountID }
            .filter { status == nil || $0.status == status }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func updateStatus(id: MailDraftID, status: MailDraftStatus, lastSendError: String?, sentReceiptID: String?) async throws -> MailDraft {
        var snapshot = try loadSnapshot()
        guard let index = snapshot.drafts.firstIndex(where: { $0.id == id }) else { throw MailRuntimeError.draftNotFound(id.rawValue) }
        var draft = snapshot.drafts[index]
        draft.status = status
        draft.lastSendError = lastSendError
        draft.sentReceiptID = sentReceiptID
        draft.updatedAt = Date()
        snapshot.drafts[index] = draft
        try saveSnapshot(snapshot)
        return draft
    }

    public func updateApprovedEnvelopeHash(id: MailDraftID, envelopeHash: String?) async throws -> MailDraft {
        var snapshot = try loadSnapshot()
        guard let index = snapshot.drafts.firstIndex(where: { $0.id == id }) else { throw MailRuntimeError.draftNotFound(id.rawValue) }
        var draft = snapshot.drafts[index]
        draft.approvedEnvelopeHash = envelopeHash
        draft.updatedAt = Date()
        snapshot.drafts[index] = draft
        try saveSnapshot(snapshot)
        return draft
    }

    public func discard(id: MailDraftID) async throws -> MailDraft {
        try await updateStatus(id: id, status: .discarded)
    }

    public func recordSendAttempt(_ attempt: MailSendAttempt) async throws {
        var snapshot = try loadSnapshot()
        snapshot.attempts.append(attempt)
        try saveSnapshot(snapshot)
    }

    public func sendAttempts(draftID: MailDraftID) async throws -> [MailSendAttempt] {
        try loadSnapshot().attempts.filter { $0.draftID == draftID }.sorted { $0.createdAt < $1.createdAt }
    }

    private func loadSnapshot() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return Snapshot() }
        let data = try Data(contentsOf: storeURL)
        if data.isEmpty { return Snapshot() }
        return try decoder.decode(Snapshot.self, from: data)
    }

    private func saveSnapshot(_ snapshot: Snapshot) throws {
        let directory = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: storeURL, options: [.atomic])
    }
}

public typealias MailDraftStore = InMemoryMailDraftRepository
