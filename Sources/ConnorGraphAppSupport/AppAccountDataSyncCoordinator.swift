import Foundation
import CryptoKit
import ConnorGraphCore
import ConnorGraphStore

public enum AppAccountSyncSignal {
    @TaskLocal public static var suppressLocalChange = false
    public static let localDataDidChange = Notification.Name("ConnorAccountSyncLocalDataDidChange")

    public static func postLocalDataDidChange() {
        guard !suppressLocalChange else { return }
        // 后台写线程（导入、会话保存等）不应阻塞等待主线程上的观察者：
        // 主线程繁忙/卡在布局时，同步投递会让写路径在通知处永久等待。
        // 改为异步投递，观察者仍按注册的 queue(.main) 收到通知。
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: localDataDidChange, object: nil)
        }
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
        let remote = AgentSession(
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
        guard let existing else { return remote }
        // 合并同步按“最后更新者生效”（与 Android mergeSyncedSession 对齐）：
        // updatedAt 更新的记录决定标题、状态与归档；消息是追加式数据，
        // 两端按 id 去重后按时间排序合并，远端旧投影不会覆盖本机尚未上传的消息。
        let localIsNewer = existing.updatedAt > remote.updatedAt
        let preferred = localIsNewer ? existing : remote
        let secondary = localIsNewer ? remote : existing
        var merged = preferred
        var messagesByID: [String: AgentMessage] = [:]
        // 同 id 消息以“createdAt 较新的一侧”为准（与 Android mergeSyncedSession 对齐）：
        // 流式草稿与最终回复复用同一 id 时，最终文本（createdAt 更晚）会覆盖旧内容，
        // 而不是把“last-writer-wins 更旧一侧”的半条草稿保留下来。
        for message in preferred.messages + secondary.messages {
            if let existing = messagesByID[message.id] {
                if message.createdAt > existing.createdAt {
                    messagesByID[message.id] = message
                }
            } else {
                messagesByID[message.id] = message
            }
        }
        merged.messages = messagesByID.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            // 同一毫秒内的用户提问/助手回复按角色稳定排序（用户消息在前），
            // 避免用随机 UUID 决定顺序导致问答颠倒。
            if $0.role != $1.role { return $0.role == .user }
            return $0.id < $1.id
        }
        // 标签按“两端并集”合并：一方没有的标签直接补上（与 Android mergeSyncedSession 对齐），
        // 去重且保持顺序稳定；状态等冲突字段仍由最后更新者决定。
        var unionedLabels: [AgentSessionLabel] = []
        var seenLabelIDs = Set<String>()
        for label in preferred.governance.labels + secondary.governance.labels where !seenLabelIDs.contains(label.id) {
            seenLabelIDs.insert(label.id)
            unionedLabels.append(label)
        }
        merged.governance.labels = unionedLabels
        return merged
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

/// RSS 订阅源跨端共享线格式：只含 id/feedURL/displayName/createdAt/updatedAt，
/// 分组、阅读状态、健康度等本机状态不参与账号同步。
public struct SyncRSSSubscription: Codable, Sendable, Equatable {
    public var id: String
    public var feedURL: String
    public var title: String
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(_ source: RSSSource) {
        id = source.id.rawValue
        feedURL = source.feedURL.absoluteString
        title = source.displayName
        createdAt = Int64(source.createdAt.timeIntervalSince1970 * 1_000)
        updatedAt = Int64(source.updatedAt.timeIntervalSince1970 * 1_000)
    }

    /// 合并回 RSSSource：优先保留本机源的分组/阅读状态等字段，只覆盖共享字段。
    static func makeSource(_ wire: SyncRSSSubscription, local: RSSSource?) -> RSSSource {
        if var source = local {
            if let url = URL(string: wire.feedURL) { source.feedURL = url }
            source.displayName = wire.title.isEmpty ? (source.feedURL.host ?? source.feedURL.absoluteString) : wire.title
            source.createdAt = Date(timeIntervalSince1970: Double(wire.createdAt) / 1_000)
            source.updatedAt = Date(timeIntervalSince1970: Double(wire.updatedAt) / 1_000)
            return source
        }
        let url = URL(string: wire.feedURL) ?? URL(string: "https://invalid.local")!
        return RSSSource(
            id: RSSSourceID(rawValue: wire.id),
            feedURL: url,
            displayName: wire.title.isEmpty ? (url.host ?? url.absoluteString) : wire.title,
            createdAt: Date(timeIntervalSince1970: Double(wire.createdAt) / 1_000),
            updatedAt: Date(timeIntervalSince1970: Double(wire.updatedAt) / 1_000)
        )
    }
}

public struct AppAccountDataSyncResult: Sendable, Equatable {
    public var appliedSessionChangeCount: Int
    public var appliedSettingsChangeCount: Int
    public var appliedGovernanceLabelChangeCount: Int
    public var appliedRSSChangeCount: Int
    public var pushedChangeCount: Int
    public var appliedSessionIDs: Set<String>

    public init(appliedSessionChangeCount: Int = 0, appliedSettingsChangeCount: Int = 0, appliedGovernanceLabelChangeCount: Int = 0, appliedRSSChangeCount: Int = 0, pushedChangeCount: Int = 0, appliedSessionIDs: Set<String> = []) {
        self.appliedSessionChangeCount = appliedSessionChangeCount
        self.appliedSettingsChangeCount = appliedSettingsChangeCount
        self.appliedGovernanceLabelChangeCount = appliedGovernanceLabelChangeCount
        self.appliedRSSChangeCount = appliedRSSChangeCount
        self.pushedChangeCount = pushedChangeCount
        self.appliedSessionIDs = appliedSessionIDs
    }

    public var sessionsChanged: Bool { appliedSessionChangeCount > 0 || !appliedSessionIDs.isEmpty }
    public var settingsChanged: Bool { appliedSettingsChangeCount > 0 }
    public var governanceLabelsChanged: Bool { appliedGovernanceLabelChangeCount > 0 }
    public var rssChanged: Bool { appliedRSSChangeCount > 0 }
}

public actor AppAccountDataSyncCoordinator {
    /// 账号同步只承载这些集合；真人私聊/群聊及其消息由 IM 专用接口按需同步，
    /// 不得进入账号同步流。拉取时先过滤，避免历史残留的 IM 集合污染同步状态。
    private enum SyncCollection {
        static let sessions = "sessions"
        static let settings = "settings"
        static let memoryL0 = "memory_l0"
        static let memoryL0Spans = "memory_l0_spans"
        static let memoryL1 = "memory_l1"
        static let memoryL2 = "memory_l2"
        static let memoryL2Nodes = "memory_l2_nodes"
        static let memoryL3 = "memory_l3"
        static let memoryL4Entities = "memory_l4_entities"
        static let memoryL4Relations = "memory_l4_relations"
        static let skills = "skills"
        static let governanceLabels = "governance_labels"
        static let rssSubscriptions = "rss_subscriptions"
    }

    /// 记录级同步边界：sessions 全量同步；settings 同步运行时设置、人格与用户偏好；
    /// governance_labels 同步会话标签定义（名称/颜色/图标）；Memory OS L2/L3/L4 全量同步，L1 会话工作记忆只留本机。
    /// rss_subscriptions 同步 RSS 订阅源（id/feedURL/displayName/createdAt/updatedAt），删除同样传播。
    /// 个人资料 settings|profile 不进同步状态机，拉取时不记录、不应用，
    /// 历史残留也不会再触发 tombstone。
    private func isSyncableRecord(_ collection: String, _ recordId: String) -> Bool {
        switch collection {
        case SyncCollection.sessions: return true
        case SyncCollection.settings: return recordId == "macos_runtime" || recordId == "personality" || recordId == "user_preferences"
        case SyncCollection.governanceLabels: return true
        case SyncCollection.rssSubscriptions: return true
        case SyncCollection.memoryL0, SyncCollection.memoryL0Spans, SyncCollection.memoryL1: return true
        case "memory_l2", "memory_l2_nodes", "memory_l3", "memory_l4_entities", "memory_l4_relations": return true
        case SyncCollection.skills: return true
        default: return false
        }
    }

    private enum AppliedChangeKind { case session(String), settings, governanceLabels, rssSubscriptions }
    private struct RecordState: Codable { var version: Int64; var hash: String; var deleted: Bool; var encrypted: Bool = false }
    private struct PersistedState: Codable { var cursor: Int64 = 0; var records: [String: RecordState] = [:] }

    private let sessions: AppChatSessionRepository
    private let settings: AppRuntimeSettingsRepository
    private let governance: AppSessionGovernanceConfigRepository?
    private let memory: SQLiteMemoryOSStore?
    private let skillStore: SkillSyncStore?
    private let rss: (any RSSSourceRepository)?
    private let identity: AppUserIdentityStore
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(sessions: AppChatSessionRepository, settings: AppRuntimeSettingsRepository, governance: AppSessionGovernanceConfigRepository? = nil, memory: SQLiteMemoryOSStore?, skillStore: SkillSyncStore? = nil, rss: (any RSSSourceRepository)? = nil, identity: AppUserIdentityStore, defaults: UserDefaults = .standard) {
        self.sessions = sessions; self.settings = settings; self.governance = governance; self.memory = memory; self.skillStore = skillStore; self.rss = rss; self.identity = identity; self.defaults = defaults
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
                // 合并同步：除技能包与 L0/L1 记忆层（按“最新操作优先”应用删除）外，
                // 标签定义也按“最新操作优先”应用删除；其它记忆/会话等记录不会被同步删除。
                let isTombstoneCollection = change.collection == SyncCollection.skills
                    || change.collection == SyncCollection.memoryL0
                    || change.collection == SyncCollection.memoryL0Spans
                    || change.collection == SyncCollection.memoryL1
                    || change.collection == SyncCollection.governanceLabels
                    || change.collection == SyncCollection.rssSubscriptions
                guard !change.deleted || isTombstoneCollection else { continue }
                do {
                    let clear: (change: ConnorSyncChange, encrypted: Bool)
                    if change.deleted && isTombstoneCollection {
                        let decrypted = try cipher.decrypt(change.payload, collection: change.collection, recordID: change.recordId)
                        var copy = change
                        copy.payload = decrypted.payload
                        clear = (copy, decrypted.encrypted)
                    } else {
                        clear = try decrypted(change, using: cipher)
                    }
                    if change.sourceDeviceId != deviceID, let kind = try await AppAccountSyncSignal.$suppressLocalChange.withValue(true, operation: { try await apply(clear.change) }) {
                        record(kind, in: &syncResult)
                    }
                    let key = recordKey(change.collection, change.recordId)
                    state.records[key] = RecordState(version: change.version ?? 0, hash: "", deleted: change.deleted, encrypted: clear.encrypted)
                    appliedKeys.append(key)
                } catch {
                    // 单条坏载荷（解密/解码/应用失败）不拖垮整轮同步：跳过并继续，
                    // 游标照常推进，避免一条毒记录让该设备永久卡在同一个 pull 页。
                    AppPerformanceLog.chatTurnLogger.warning("account.sync.apply-skipped collection=\(change.collection, privacy: .public) record=\(change.recordId, privacy: .public) error=\(String(describing: error), privacy: .public)")
                }
            }
            state.cursor = page.nextCursor; hasMore = page.hasMore
            saveState(state, key: stateKey)
        } while hasMore

        let projected = try await projections()
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
            let encrypted = try cipher.encrypt(payload, collection: parts[0], recordID: parts[1])
            // 超过 1 MiB 的记录跳过不推（后端对整批中的超限条目同样只跳过、不报错），
            // 避免一条超大载荷永久阻塞该账号所有设备的同步。
            guard try encoder.encode(encrypted).count <= 1_048_576 else {
                AppPerformanceLog.chatTurnLogger.warning("account.sync.payload-too-large collection=\(parts[0], privacy: .public) record=\(parts[1], privacy: .public)")
                continue
            }
            mutations.append(try ConnorSyncChange(collection: parts[0], recordId: parts[1], baseVersion: state.records[key]?.version ?? 0, payload: encrypted))
        }
        // 技能包与 L0/L1/标签按“最新操作优先”：本地已删除且此前同步过的记录回推 tombstone（载荷带删除时间）。
        // 集合级防护：本机该集合投影完全为空时不回推 tombstone——空列表更可能是本地数据
        // 丢失/列表被清空，而不是“删光了全部”，避免一台空设备把其它端的数据也清掉。
        // RSS 订阅源不走这里：它使用显式删除标记（pendingDeletes），见下方单独逻辑。
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1_000)
        let tombstonePrefixes = ["skills|", "memory_l0|", "memory_l0_spans|", "memory_l1|", "governance_labels|"]
        let projectedCollections = Set(projected.keys.map { String($0.split(separator: "|", maxSplits: 1)[0]) })
        for key in state.records.keys where tombstonePrefixes.contains(where: { key.hasPrefix($0) }) {
            guard state.records[key]?.deleted != true, projected[key] == nil else { continue }
            let collection = String(key.split(separator: "|", maxSplits: 1)[0])
            guard projectedCollections.contains(collection) else { continue }
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            let tombstone = SyncTombstone(updatedAt: nowMillis)
            mutations.append(try ConnorSyncChange(
                collection: parts[0],
                recordId: parts[1],
                baseVersion: state.records[key]?.version ?? 0,
                payload: cipher.encrypt(jsonValue(tombstone), collection: parts[0], recordID: parts[1]),
                deleted: true
            ))
        }
        // RSS 订阅源：只对“本机显式删除”（用户在 RSS 列表里删除）回推 tombstone，
        // 删除时间取标记时间而不是当前时间。本地列表被清空/文件丢失时不产生标记，
        // 因此不会把“我这边空了”当成“全都删了”传播到其它设备。
        var rssTombstoneKeys: [String: RSSSourceID] = [:]
        if let rss {
            for (sourceID, deletedAt) in try await rss.pendingDeletes() {
                let key = recordKey(SyncCollection.rssSubscriptions, sourceID.rawValue)
                guard let record = state.records[key], !record.deleted else {
                    try? await rss.clearPendingDelete(id: sourceID)
                    continue
                }
                // 删除后又重新订阅（同 URL 同 id）→ 本地已恢复，撤消待回推删除。
                guard projected[key] == nil else {
                    try? await rss.clearPendingDelete(id: sourceID)
                    continue
                }
                let tombstone = SyncTombstone(updatedAt: deletedAt)
                mutations.append(try ConnorSyncChange(
                    collection: SyncCollection.rssSubscriptions,
                    recordId: sourceID.rawValue,
                    baseVersion: record.version,
                    payload: cipher.encrypt(jsonValue(tombstone), collection: SyncCollection.rssSubscriptions, recordID: sourceID.rawValue),
                    deleted: true
                ))
                rssTombstoneKeys[key] = sourceID
            }
        }

        for batch in mutations.chunked(into: 200) {
            let results = try await identity.pushSyncChanges(batch)
            for (pushResult, mutation) in zip(results, batch) where pushResult.applied {
                let clear = try cipher.decrypt(mutation.payload, collection: mutation.collection, recordID: mutation.recordId)
                state.records[recordKey(mutation.collection, mutation.recordId)] = RecordState(version: (mutation.baseVersion ?? 0) + 1, hash: try payloadHash(clear.payload), deleted: mutation.deleted, encrypted: true)
                syncResult.pushedChangeCount += 1
                if let sourceID = rssTombstoneKeys[recordKey(mutation.collection, mutation.recordId)] {
                    try? await rss?.clearPendingDelete(id: sourceID)
                }
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

    private func projections() async throws -> [String: ConnorJSONValue] {
        var values: [String: ConnorJSONValue] = [:]
        for session in try sessions.loadSessions(filter: .all) {
            values[recordKey("sessions", session.id)] = try jsonValue(ConnorPortableSession(session))
        }
        let runtimeSettings = try settings.loadOrCreateDefault()
        values[recordKey("settings", "personality")] = try jsonValue(SyncPersonality(runtimeSettings))
        values[recordKey("settings", "user_preferences")] = try jsonValue(
            SyncUserPreferences(
                runtimeSettings.preferences,
                updatedAtMillis: Int64(runtimeSettings.updatedAt.timeIntervalSince1970 * 1_000)
            )
        )
        var syncedSettings = runtimeSettings
        // 个人资料（preferences：displayName/notes 等）不加入账号同步，仅同步运行时设置。
        syncedSettings.preferences = AgentRuntimePreferenceSettings()
        values[recordKey("settings", "macos_runtime")] = try jsonValue(syncedSettings)
        if let memory {
            for provenance in try memory.listAllProvenanceObjects() {
                values[recordKey(SyncCollection.memoryL0, provenance.id)] = try jsonValue(SyncL0Provenance(provenance: provenance))
            }
            for span in try memory.listAllProvenanceSpans() {
                values[recordKey(SyncCollection.memoryL0Spans, span.id)] = try jsonValue(SyncL0Span(span: span))
            }
            for event in try memory.listAllCaptureEvents().filter({ $0.processingState == .pending }) {
                values[recordKey(SyncCollection.memoryL1, event.id)] = try jsonValue(SyncL1Capture(event: event))
            }
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
        if let skillStore {
            for pack in try skillStore.listUserPacks() {
                values[recordKey(SyncCollection.skills, pack.id)] = try jsonValue(pack)
            }
        }
        // 会话标签定义（名称/颜色/图标）随账号同步：以最近编辑时间合并，删除同样传播。
        if let governance {
            let config = try governance.loadOrCreateDefault()
            for label in config.labels {
                values[recordKey(SyncCollection.governanceLabels, label.id)] = try jsonValue(label)
            }
        }
        // RSS 订阅源：只同步跨端共享字段（id/feedURL/displayName/createdAt/updatedAt），
        // 分组/阅读状态/健康度等本机状态不参与账号同步。
        if let rss {
            for source in try await rss.listSources() {
                values[recordKey(SyncCollection.rssSubscriptions, source.id.rawValue)] = try jsonValue(SyncRSSSubscription(source))
            }
        }
        return values
    }

    private func apply(_ change: ConnorSyncChange) async throws -> AppliedChangeKind? {
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
        case ("settings", "personality"):
            let wire: SyncPersonality = try decode(change.payload)
            try settings.applySyncedPersonality(wire.connorPersonality(), revision: wire.revision ?? 0, updatedAtMillis: wire.updatedAt ?? 0)
            return .settings
        case ("settings", "user_preferences") where !change.deleted:
            // 用户偏好按“最后设置时间”生效：远端不晚于本机设置时间则忽略；
            // 应用时只覆盖两端共有字段，保留本机独有字段。
            let wire: SyncUserPreferences = try decode(change.payload)
            let local = try settings.loadOrCreateDefault()
            let remoteMillis = wire.updatedAt
            let localMillis = Int64(local.updatedAt.timeIntervalSince1970 * 1_000)
            if remoteMillis > localMillis {
                var synced = local
                synced.preferences = wire.applying(to: local.preferences)
                try settings.saveSynced(synced)
            }
            return .settings
        case ("memory_l0", let id):
            guard let memory else { return nil }
            try memory.withForeignKeysDisabled {
                if change.deleted {
                    try memory.deleteProvenanceObject(id: id)
                } else {
                    let wire: SyncL0Provenance = try decode(change.payload)
                    try memory.upsert(provenance: wire.makeProvenance())
                }
            }
            return nil
        case ("memory_l0_spans", let id):
            guard let memory else { return nil }
            try memory.withForeignKeysDisabled {
                if change.deleted {
                    try memory.deleteSpan(id: id)
                } else {
                    let wire: SyncL0Span = try decode(change.payload)
                    try memory.upsert(span: wire.makeSpan())
                }
            }
            return nil
        case ("memory_l1", let id):
            guard let memory else { return nil }
            try memory.withForeignKeysDisabled {
                if change.deleted {
                    try memory.deleteCaptureEvent(id: id)
                } else if let wire: SyncL1Capture = try? decode(change.payload) {
                    try memory.upsert(captureEvent: wire.makeCaptureEvent())
                } else {
                    // 历史后端曾把 tombstone 的 deleted 恒置 false，载荷只剩 updatedAt，
                    // 无法按 SyncL1Capture 解码。L1 是可重建的临时工作记忆（L0 永久保留），
                    // 这里按删除意图处理，避免同步卡死在“必填字段缺失”。
                    try memory.deleteCaptureEvent(id: id)
                }
            }
            return nil
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
        case ("skills", let id):
            guard let skillStore else { return nil }
            if change.deleted {
                let tombstone: SyncSkillTombstone = try decode(change.payload)
                let local = try skillStore.pack(id: id)
                if tombstone.updatedAt > (local?.updatedAt ?? 0) {
                    try skillStore.delete(id: id)
                }
            } else {
                let wire: SyncSkillPack = try decode(change.payload)
                let local = try skillStore.pack(id: id)
                if local == nil || wire.updatedAt > local!.updatedAt {
                    try skillStore.apply(wire)
                }
            }
            return nil
        case ("governance_labels", let id):
            guard let governance else { return nil }
            var config = try governance.loadOrCreateDefault()
            if change.deleted {
                // 删除按“最新操作优先”：远端删除时间比本地编辑时间新才删除。
                let tombstone: SyncTombstone = try decode(change.payload)
                let local = config.labels.first { $0.id == id }
                if tombstone.updatedAt > (local?.updatedAt ?? 0) {
                    config.labels.removeAll { $0.id == id }
                    try governance.save(config)
                    return .governanceLabels
                }
            } else {
                let wire: AgentSessionLabelDefinition = try decode(change.payload)
                let local = config.labels.first { $0.id == id }
                if local == nil || wire.updatedAt > local!.updatedAt {
                    if let index = config.labels.firstIndex(where: { $0.id == id }) {
                        config.labels[index] = wire
                    } else {
                        config.labels.append(wire)
                    }
                    try governance.save(config)
                    return .governanceLabels
                }
            }
            return nil
        case ("rss_subscriptions", let id):
            guard let rss else { return nil }
            let sourceID = RSSSourceID(rawValue: id)
            if change.deleted {
                // 删除按“最新操作优先”：远端删除时间比本地编辑时间新才删除。
                let tombstone: SyncTombstone = try decode(change.payload)
                let local = try await rss.source(id: sourceID)
                if tombstone.updatedAt > Int64((local?.updatedAt ?? .distantPast).timeIntervalSince1970 * 1_000) {
                    try await rss.applyRemoteDelete(id: sourceID)
                    try? await rss.clearPendingDelete(id: sourceID)
                    return .rssSubscriptions
                }
            } else {
                let wire: SyncRSSSubscription = try decode(change.payload)
                // URL 去重：同 URL 已存在不同 id（历史版本）时按“后更新者胜”，
                // 采用胜者 id，避免跨端出现重复订阅。
                let sources = try await rss.listSources()
                if let byURL = sources.first(where: { $0.feedURL.absoluteString == wire.feedURL && $0.id.rawValue != id }) {
                    if wire.updatedAt > Int64(byURL.updatedAt.timeIntervalSince1970 * 1_000) {
                        // 去重替换是远端驱动的合并，不是用户删除：不产生删除标记。
                        try await rss.applyRemoteDelete(id: byURL.id)
                        try await rss.saveSource(SyncRSSSubscription.makeSource(wire, local: nil))
                    }
                    return .rssSubscriptions
                }
                let local = try await rss.source(id: sourceID)
                if wire.updatedAt > Int64((local?.updatedAt ?? .distantPast).timeIntervalSince1970 * 1_000) {
                    try await rss.saveSource(SyncRSSSubscription.makeSource(wire, local: local))
                    return .rssSubscriptions
                }
            }
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
        case .governanceLabels: result.appliedGovernanceLabelChangeCount += 1
        case .rssSubscriptions: result.appliedRSSChangeCount += 1
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
