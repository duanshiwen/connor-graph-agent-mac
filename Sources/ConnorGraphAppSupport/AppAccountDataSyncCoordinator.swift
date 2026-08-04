import Foundation
import CryptoKit
import ConnorGraphCore
import ConnorGraphStore

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
        static let memoryL2 = "memory_l2"
        static let memoryL2Nodes = "memory_l2_nodes"
        static let memoryL3 = "memory_l3"
        static let memoryL4Entities = "memory_l4_entities"
        static let memoryL4Relations = "memory_l4_relations"
    }

    /// 记录级同步边界：sessions 全量同步；settings 仅同步运行时设置与人格
    /// （人格只记录不上推）；Memory OS L2/L3/L4 全量同步，L1 会话工作记忆只留本机。
    /// 个人资料 settings|profile 不进同步状态机，拉取时不记录、不应用，
    /// 历史残留也不会再触发 tombstone。
    private func isSyncableRecord(_ collection: String, _ recordId: String) -> Bool {
        switch collection {
        case SyncCollection.sessions: return true
        case SyncCollection.settings: return recordId == "macos_runtime" || recordId == "personality"
        case "memory_l2", "memory_l2_nodes", "memory_l3", "memory_l4_entities", "memory_l4_relations": return true
        default: return false
        }
    }

    private enum AppliedChangeKind { case session(String), settings }
    private struct RecordState: Codable { var version: Int64; var hash: String; var deleted: Bool; var encrypted: Bool = false }
    private struct PersistedState: Codable { var cursor: Int64 = 0; var records: [String: RecordState] = [:] }

    private let sessions: AppChatSessionRepository
    private let settings: AppRuntimeSettingsRepository
    private let memory: SQLiteMemoryOSStore?
    private let identity: AppUserIdentityStore
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(sessions: AppChatSessionRepository, settings: AppRuntimeSettingsRepository, memory: SQLiteMemoryOSStore?, identity: AppUserIdentityStore, defaults: UserDefaults = .standard) {
        self.sessions = sessions; self.settings = settings; self.memory = memory; self.identity = identity; self.defaults = defaults
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
        var appliedKeys: [String] = []
        repeat {
            let page = try await identity.pullSyncChanges(cursor: state.cursor)
            for change in page.changes where isSyncableRecord(change.collection, change.recordId) {
                // 合并同步：tombstone 一律跳过，任何端都不会因同步删除记录。
                guard !change.deleted else { continue }
                let clear = try decrypted(change, using: cipher)
                if change.sourceDeviceId != deviceID, let kind = try AppAccountSyncSignal.$suppressLocalChange.withValue(true, operation: { try apply(clear.change) }) {
                    record(kind, in: &syncResult)
                }
                let key = recordKey(change.collection, change.recordId)
                state.records[key] = RecordState(version: change.version ?? 0, hash: "", deleted: false, encrypted: clear.encrypted)
                appliedKeys.append(key)
            }
            state.cursor = page.nextCursor; hasMore = page.hasMore
            saveState(state, key: stateKey)
        } while hasMore

        let projected = try projections()
        // 状态哈希回填为“本地重新编码后的投影”哈希，而不是远端载荷哈希：
        // 两端编码（键序/日期格式/可选字段）不同，若保存远端载荷哈希，下一次投影
        // 比较必然不相等，会把刚收到的记录又推回去，形成两端无限互推。
        for key in appliedKeys {
            guard var record = state.records[key], let payload = projected[key] else { continue }
            record.hash = try payloadHash(payload)
            state.records[key] = record
        }
        var mutations: [ConnorSyncChange] = []
        for (key, payload) in projected where state.records[key]?.hash != (try payloadHash(payload)) || state.records[key]?.encrypted != true {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            mutations.append(try ConnorSyncChange(collection: parts[0], recordId: parts[1], baseVersion: state.records[key]?.version ?? 0, payload: cipher.encrypt(payload, collection: parts[0], recordID: parts[1])))
        }

        for batch in mutations.chunked(into: 200) {
            let results = try await identity.pushSyncChanges(batch)
            for (pushResult, mutation) in zip(results, batch) where pushResult.applied {
                let clear = try cipher.decrypt(mutation.payload, collection: mutation.collection, recordID: mutation.recordId)
                state.records[recordKey(mutation.collection, mutation.recordId)] = RecordState(version: (mutation.baseVersion ?? 0) + 1, hash: try payloadHash(clear.payload), deleted: false, encrypted: true)
                syncResult.pushedChangeCount += 1
            }
        }
        // 清理历史残留（settings|profile 等不可同步记录），避免重新进入同步状态机。
        state.records = state.records.filter { entry in
            let parts = entry.key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return false }
            return isSyncableRecord(parts[0], parts[1])
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
        var syncedSettings = runtimeSettings
        // 个人资料（preferences：displayName/notes 等）不加入账号同步，仅同步运行时设置。
        syncedSettings.preferences = AgentRuntimePreferenceSettings()
        values[recordKey("settings", "macos_runtime")] = try jsonValue(syncedSettings)
        if let memory {
            for statement in try memory.listAllStatements() {
                values[recordKey(SyncCollection.memoryL2, statement.id)] = try jsonValue(SyncMemoryL2Statement(statement))
            }
            for node in try memory.listAllNodes() {
                values[recordKey(SyncCollection.memoryL2Nodes, node.id)] = try jsonValue(SyncMemoryL2Node(node))
            }
            for belief in try memory.listAllBeliefs() {
                values[recordKey(SyncCollection.memoryL3, belief.id)] = try jsonValue(SyncMemoryL3Belief(belief))
            }
            for entity in try memory.listAllEntities() {
                values[recordKey(SyncCollection.memoryL4Entities, entity.id)] = try jsonValue(SyncMemoryL4Entity(entity))
            }
            for relation in try memory.listAllEntityStatements() {
                values[recordKey(SyncCollection.memoryL4Relations, relation.id)] = try jsonValue(SyncMemoryL4Relation(relation))
            }
        }
        return values
    }

    private func apply(_ change: ConnorSyncChange) throws -> AppliedChangeKind? {
        switch (change.collection, change.recordId) {
        // 合并同步：任何端都不会因同步删除记录；远端变化一律合并落库。
        case ("sessions", let id):
            let portable: ConnorPortableSession = try decode(change.payload)
            _ = try sessions.saveSession(portable.merging(into: try sessions.loadSession(id: id)))
            return .session(id)
        case ("settings", "macos_runtime") where !change.deleted:
            var synced: AgentRuntimeSettings = try decode(change.payload)
            synced.preferences = try settings.loadOrCreateDefault().preferences
            try settings.save(synced)
            return .settings
        case ("memory_l2", _):
            guard let memory else { return nil }
            let wire: SyncMemoryL2Statement = try decode(change.payload)
            try memory.withForeignKeysDisabled { try memory.upsert(statement: wire.makeStatement()) }
            return nil
        case ("memory_l2_nodes", _):
            guard let memory else { return nil }
            let wire: SyncMemoryL2Node = try decode(change.payload)
            try memory.withForeignKeysDisabled { try memory.upsert(node: wire.makeNode()) }
            return nil
        case ("memory_l3", _):
            guard let memory else { return nil }
            let wire: SyncMemoryL3Belief = try decode(change.payload)
            try memory.withForeignKeysDisabled { try memory.upsert(belief: wire.makeBelief()) }
            return nil
        case ("memory_l4_entities", _):
            guard let memory else { return nil }
            let wire: SyncMemoryL4Entity = try decode(change.payload)
            try memory.withForeignKeysDisabled { try memory.upsert(entity: wire.makeEntity()) }
            return nil
        case ("memory_l4_relations", _):
            guard let memory else { return nil }
            let wire: SyncMemoryL4Relation = try decode(change.payload)
            try memory.withForeignKeysDisabled { try memory.upsert(entityStatement: wire.makeEntityStatement()) }
            return nil
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
