import Foundation
import CryptoKit
import ConnorGraphCore

public enum AppAccountSyncSignal {
    @TaskLocal public static var suppressLocalChange = false
    public static let localDataDidChange = Notification.Name("ConnorAccountSyncLocalDataDidChange")

    public static func postLocalDataDidChange() {
        guard !suppressLocalChange else { return }
        NotificationCenter.default.post(name: localDataDidChange, object: nil)
    }
}

public struct ConnorPortableMessage: Codable, Sendable, Equatable {
    public var id: String
    public var role: String
    public var content: String
    public var createdAt: Int64
    public var status: String
}

public struct ConnorPortableSession: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var status: String
    public var archived: Bool
    public var labels: [String]
    public var messages: [ConnorPortableMessage]

    public init(_ session: AgentSession) {
        id = session.id; title = session.title
        createdAt = Int64(session.createdAt.timeIntervalSince1970 * 1_000)
        updatedAt = Int64(session.updatedAt.timeIntervalSince1970 * 1_000)
        status = session.governance.status.rawValue; archived = session.governance.isArchived
        labels = session.governance.labels.map(\.id)
        messages = session.messages.map {
            ConnorPortableMessage(id: $0.id, role: $0.role.rawValue, content: $0.content, createdAt: Int64($0.createdAt.timeIntervalSince1970 * 1_000), status: "complete")
        }
    }

    public func merging(into existing: AgentSession?) -> AgentSession {
        var governance = existing?.governance ?? .default
        governance.status = AgentSessionStatus(rawValue: status) ?? .todo
        governance.isArchived = archived
        governance.labels = labels.map(AgentSessionLabel.init(id:))
        return AgentSession(
            id: id, title: title,
            messages: messages.compactMap { message in
                guard let role = AgentRole(rawValue: message.role) else { return nil }
                return AgentMessage(id: message.id, role: role, content: message.content, createdAt: Date(timeIntervalSince1970: Double(message.createdAt) / 1_000))
            },
            createdAt: Date(timeIntervalSince1970: Double(createdAt) / 1_000),
            updatedAt: Date(timeIntervalSince1970: Double(updatedAt) / 1_000),
            governance: governance,
            readState: existing?.readState ?? .initial(updatedAt: Date(timeIntervalSince1970: Double(updatedAt) / 1_000))
        )
    }
}

public struct ConnorPortableProfile: Codable, Sendable, Equatable {
    public var memoryProfile: String
    public var installedKnowledgePackIds: Set<String>

    public init(memoryProfile: String, installedKnowledgePackIds: Set<String> = []) {
        self.memoryProfile = memoryProfile
        self.installedKnowledgePackIds = installedKnowledgePackIds
    }
}

public struct AppAccountDataSyncResult: Sendable, Equatable {
    public var appliedSessionChangeCount: Int
    public var appliedSettingsChangeCount: Int
    public var pushedChangeCount: Int
    public var appliedSessionIDs: Set<String>

    public init(appliedSessionChangeCount: Int = 0, appliedSettingsChangeCount: Int = 0, pushedChangeCount: Int = 0, appliedSessionIDs: Set<String> = []) {
        self.appliedSessionChangeCount = appliedSessionChangeCount
        self.appliedSettingsChangeCount = appliedSettingsChangeCount
        self.pushedChangeCount = pushedChangeCount
        self.appliedSessionIDs = appliedSessionIDs
    }

    public var sessionsChanged: Bool { appliedSessionChangeCount > 0 || !appliedSessionIDs.isEmpty }
    public var settingsChanged: Bool { appliedSettingsChangeCount > 0 }
}

public actor AppAccountDataSyncCoordinator {
    /// 账号同步只承载这些集合；真人私聊/群聊及其消息由 IM 专用接口按需同步，
    /// 不得进入账号同步流。拉取时先过滤，避免历史残留的 IM 集合污染同步状态。
    private enum SyncCollection {
        static let sessions = "sessions"
        static let settings = "settings"
        static let allowed: Set<String> = [sessions, settings]
    }

    private enum AppliedChangeKind { case session(String), settings }
    private struct RecordState: Codable { var version: Int64; var hash: String; var deleted: Bool; var encrypted: Bool = false }
    private struct PersistedState: Codable { var cursor: Int64 = 0; var records: [String: RecordState] = [:] }

    private let sessions: AppChatSessionRepository
    private let settings: AppRuntimeSettingsRepository
    private let identity: AppUserIdentityStore
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(sessions: AppChatSessionRepository, settings: AppRuntimeSettingsRepository, identity: AppUserIdentityStore, defaults: UserDefaults = .standard) {
        self.sessions = sessions; self.settings = settings; self.identity = identity; self.defaults = defaults
        encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    }

    public func reconcile() async throws -> AppAccountDataSyncResult {
        guard let userID = await identity.currentUser?.id else { return AppAccountDataSyncResult() }
        let cipher = try await AccountSyncPayloadCipher(keyData: identity.accountSyncKey(userID: String(userID)))
        let deviceID = await identity.syncDeviceID
        var syncResult = AppAccountDataSyncResult()
        let stateKey = "ConnorAccountSyncState.\(userID)"
        var state = loadState(key: stateKey)
        var hasMore = false
        repeat {
            let page = try await identity.pullSyncChanges(cursor: state.cursor)
            for change in page.changes where SyncCollection.allowed.contains(change.collection) {
                let clear = try decrypted(change, using: cipher)
                if change.sourceDeviceId != deviceID, let kind = try AppAccountSyncSignal.$suppressLocalChange.withValue(true, operation: { try apply(clear.change) }) {
                    record(kind, in: &syncResult)
                }
                state.records[recordKey(change.collection, change.recordId)] = RecordState(version: change.version ?? 0, hash: try payloadHash(clear.change.payload), deleted: change.deleted, encrypted: clear.encrypted)
            }
            state.cursor = page.nextCursor; hasMore = page.hasMore
            saveState(state, key: stateKey)
        } while hasMore

        let projected = try projections()
        let syncableKeys = Set(state.records.keys.filter { $0.hasPrefix("sessions|") || $0 == "settings|macos_runtime" || $0 == "settings|profile" })
        var mutations: [ConnorSyncChange] = []
        for (key, payload) in projected where state.records[key]?.hash != (try payloadHash(payload)) || state.records[key]?.deleted == true || state.records[key]?.encrypted != true {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            mutations.append(try ConnorSyncChange(collection: parts[0], recordId: parts[1], baseVersion: state.records[key]?.version ?? 0, payload: cipher.encrypt(payload, collection: parts[0], recordID: parts[1])))
        }
        for key in syncableKeys.subtracting(projected.keys) where state.records[key]?.deleted != true {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            mutations.append(try ConnorSyncChange(collection: parts[0], recordId: parts[1], baseVersion: state.records[key]?.version ?? 0, deleted: true))
        }

        for batch in mutations.chunked(into: 200) {
            let results = try await identity.pushSyncChanges(batch)
            for (pushResult, mutation) in zip(results, batch) {
                if let conflict = pushResult.conflict {
                    let clear = try decrypted(conflict, using: cipher)
                    if let kind = try AppAccountSyncSignal.$suppressLocalChange.withValue(true, operation: { try apply(clear.change) }) { record(kind, in: &syncResult) }
                    state.records[recordKey(conflict.collection, conflict.recordId)] = RecordState(version: conflict.version ?? 0, hash: try payloadHash(clear.change.payload), deleted: conflict.deleted, encrypted: clear.encrypted)
                } else if pushResult.applied {
                    let clear = try cipher.decrypt(mutation.payload, collection: mutation.collection, recordID: mutation.recordId)
                    state.records[recordKey(mutation.collection, mutation.recordId)] = RecordState(version: (mutation.baseVersion ?? 0) + 1, hash: try payloadHash(clear.payload), deleted: mutation.deleted, encrypted: !mutation.deleted)
                    syncResult.pushedChangeCount += 1
                }
            }
        }
        saveState(state, key: stateKey)
        return syncResult
    }

    private func projections() throws -> [String: ConnorJSONValue] {
        var values: [String: ConnorJSONValue] = [:]
        for session in try sessions.loadSessions(filter: .all) {
            values[recordKey("sessions", session.id)] = try jsonValue(ConnorPortableSession(session))
        }
        let runtimeSettings = try settings.loadOrCreateDefault()
        values[recordKey("settings", "macos_runtime")] = try jsonValue(runtimeSettings)
        values[recordKey("settings", "profile")] = try jsonValue(ConnorPortableProfile(memoryProfile: runtimeSettings.preferences.notes))
        return values
    }

    private func apply(_ change: ConnorSyncChange) throws -> AppliedChangeKind? {
        switch (change.collection, change.recordId) {
        case ("sessions", let id):
            if change.deleted {
                guard try sessions.loadSession(id: id) != nil else { return nil }
                try sessions.store.deleteSession(id: id)
            } else {
                let portable: ConnorPortableSession = try decode(change.payload)
                _ = try sessions.saveSession(portable.merging(into: try sessions.loadSession(id: id)))
            }
            return .session(id)
        case ("settings", "macos_runtime") where !change.deleted:
            var synced: AgentRuntimeSettings = try decode(change.payload)
            synced.preferences = try settings.loadOrCreateDefault().preferences
            try settings.save(synced)
            return .settings
        case ("settings", "profile"):
            var runtimeSettings = try settings.loadOrCreateDefault()
            let profile = change.deleted ? ConnorPortableProfile(memoryProfile: "") : try decode(change.payload)
            runtimeSettings.preferences.notes = profile.memoryProfile
            try settings.save(runtimeSettings)
            return .settings
        default: return nil
        }
    }

    private func record(_ kind: AppliedChangeKind, in result: inout AppAccountDataSyncResult) {
        switch kind {
        case .session(let id):
            result.appliedSessionChangeCount += 1
            result.appliedSessionIDs.insert(id)
        case .settings: result.appliedSettingsChangeCount += 1
        }
    }

    private func jsonValue<T: Encodable>(_ value: T) throws -> ConnorJSONValue { try decoder.decode(ConnorJSONValue.self, from: encoder.encode(value)) }
    private func decode<T: Decodable>(_ payload: ConnorJSONValue) throws -> T { try decoder.decode(T.self, from: encoder.encode(payload)) }
    private func payloadHash(_ payload: ConnorJSONValue) throws -> String { SHA256.hash(data: try encoder.encode(payload)).map { String(format: "%02x", $0) }.joined() }
    private func decrypted(_ change: ConnorSyncChange, using cipher: AccountSyncPayloadCipher) throws -> (change: ConnorSyncChange, encrypted: Bool) {
        guard !change.deleted else { return (change, true) }
        let clear = try cipher.decrypt(change.payload, collection: change.collection, recordID: change.recordId)
        var result = change
        result.payload = clear.payload
        return (result, clear.encrypted)
    }
    private func recordKey(_ collection: String, _ id: String) -> String { "\(collection)|\(id)" }
    private func loadState(key: String) -> PersistedState { defaults.data(forKey: key).flatMap { try? decoder.decode(PersistedState.self, from: $0) } ?? PersistedState() }
    private func saveState(_ state: PersistedState, key: String) { defaults.set(try? encoder.encode(state), forKey: key) }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] { stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) } }
}
