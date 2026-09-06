import Foundation

/// M3-K8 · 新设备「应用完整重建」（v0.12 §3.4 / app-package.schema.json §newDeviceRebuild）。
///
/// 六步：① 主密钥就位 → ② 拉包状态/密钥 → ③ 拉包版本（不可变版本记录链）→ ④ 建子库 →
/// ⑤ 按序重放迁移（K6 迁移随包确定性重放）→ ⑥ 灌数据（K3 空库导入）→ ⑦ 编译 Card →
/// ⑧ 注册进能力搜索（派生查 base_apps，createApp 即注册）。按 App 幂等可重入：
/// 版本链已齐且 latest 达标且数据已灌时 no-op。
///
/// 输入为同步源拉取的明文载荷（包快照/行数据导出）；E2EE 传输（K4）在拉取层解密后进入本入口。
/// 建库按链头 v1 开始（createApp 固定写 v1 版本记录，保证指纹一致），剩余版本记录幂等补写，
/// 再 apply 目标包触发升级——重建真实走「建子库 → 重放迁移 → 灌数据」。
public struct BasePackageVersionRecord: Sendable, Equatable {
    public let snapshot: BasePackageSnapshot
    public let migrations: [Int]

    public init(snapshot: BasePackageSnapshot, migrations: [Int]) {
        self.snapshot = snapshot
        self.migrations = migrations
    }
}

/// 重建输入：同步源拉取的明文载荷。
public struct BaseRebuildInput: Sendable, Equatable {
    /// ① 主密钥（kind=master，base64 载荷；nil = 不装）。
    public let masterKeyPayload: String?
    /// ② 拉包状态/密钥（kind=app：appID → base64 载荷）。
    public let appKeys: [String: String]
    /// ③ 拉包版本：不可变版本记录链（须覆盖 1...target.packageVersion，含各版迁移序列）。
    public let packageVersionRecords: [BasePackageVersionRecord]
    /// 目标包（latest）：④ 建子库 + ⑤ 迁移重放的最终版本。
    public let targetSnapshot: BasePackageSnapshot
    /// ⑥ 灌数据（行数据导出；无数据 App 可空）。
    public let records: BaseRecordsExport?

    public init(masterKeyPayload: String?, appKeys: [String: String],
                packageVersionRecords: [BasePackageVersionRecord],
                targetSnapshot: BasePackageSnapshot, records: BaseRecordsExport?) {
        self.masterKeyPayload = masterKeyPayload
        self.appKeys = appKeys
        self.packageVersionRecords = packageVersionRecords
        self.targetSnapshot = targetSnapshot
        self.records = records
    }
}

/// 重建结果。
public struct BaseRebuildResult: Sendable, Equatable {
    public let appID: String
    /// 本次是否实际执行（false = 幂等 no-op）。
    public let rebuilt: Bool
    public let packageVersion: Int
    /// 灌入数据指纹（nil = 无数据）。
    public let recordsDigest: String?

    public init(appID: String, rebuilt: Bool, packageVersion: Int, recordsDigest: String?) {
        self.appID = appID
        self.rebuilt = rebuilt
        self.packageVersion = packageVersion
        self.recordsDigest = recordsDigest
    }
}

extension BaseLibraryStore {

    /// 新设备完整重建（幂等可重入）。
    /// 失败：版本链缺失/链头非 v1 → `MIGRATION_FAILED`（无法确定性重建）；
    /// 版本记录指纹冲突（内容寻址）→ `VERSION_MISMATCH`；数据版本不符 → `VERSION_MISMATCH`。
    @discardableResult
    public func rebuildApp(from input: BaseRebuildInput) throws -> BaseRebuildResult {
        let appID = input.targetSnapshot.appID
        guard BaseSchemaValidator.isValidAppID(appID) else {
            throw BaseError(code: .validationFailed, message: "appID 不合法", hint: "appID 须匹配 ^[a-z0-9_-]{1,48}$")
        }
        let targetVersion = input.targetSnapshot.packageVersion
        let chain = input.packageVersionRecords.sorted { $0.snapshot.packageVersion < $1.snapshot.packageVersion }
        // 版本链完整性：须恰好覆盖 1...targetVersion，且链头为 v1（createApp 固定写 v1 记录）。
        guard chain.map({ $0.snapshot.packageVersion }) == Array(1...targetVersion) else {
            throw BaseError(code: .migrationFailed, message: "重建版本链不完整",
                            hint: "须提供 1...\(targetVersion) 全部版本记录（链头 v1 起），缺失/重复无法确定性重建")
        }
        guard chain.first?.snapshot.packageVersion == 1 else {
            throw BaseError(code: .migrationFailed, message: "重建版本链缺链头",
                            hint: "版本链须从 v1 起（fresh 建库以 v1 四件套创建，createApp 固定写 v1 记录）")
        }
        // 幂等判定：入口前是否已完整重建（版本达标 + 数据已灌）。
        let wasComplete = try {
            guard try appExists(appID), try packageVersion(appID: appID) >= targetVersion else { return false }
            if let records = input.records {
                let store = try openStore(appID: appID)
                defer { store.close() }
                return try store.userTableNames().contains { try store.rowCount(in: $0) > 0 }
            }
            return true
        }()

        // ① 主密钥就位（幂等：已有则保留）。
        if let master = input.masterKeyPayload {
            try ensureKeysTable()
            if try syncKeyPayload(kind: "master", appID: "") == nil {
                try saveSyncKey(keyID: "master_key", kind: "master", appID: "", payloadJSON: master)
            }
        }
        // ② 拉包状态/密钥（幂等：已有则保留）。
        for (aid, payload) in input.appKeys {
            guard BaseSchemaValidator.isValidAppID(aid) else {
                throw BaseError(code: .validationFailed, message: "appID 不合法", hint: "appID 须匹配 ^[a-z0-9_-]{1,48}$")
            }
            try ensureKeysTable()
            if try syncKeyPayload(kind: "app", appID: aid) == nil {
                try saveSyncKey(keyID: "app_key_\(aid)", kind: "app", appID: aid, payloadJSON: payload)
            }
        }

        // ③④⑤ 建子库 + 迁移随包重放：
        // 已存在 → 先幂等补全版本链（升级路径读链），再 apply target（升级或 no-op）。
        // 不存在 → 按链头 v1 建库（createApp 写 v1 记录），幂等补链（v1 已存在跳过），
        //           target > v1 时再 apply target 触发升级重放。
        if try appExists(appID) {
            for record in chain { try writePackageVersionIdempotent(record) }
            _ = try applyPackageSnapshot(input.targetSnapshot)
        } else {
            let head = chain[0]
            _ = try applyPackageSnapshot(head.snapshot)
            for record in chain { try writePackageVersionIdempotent(record) }
            if targetVersion > 1 {
                _ = try applyPackageSnapshot(input.targetSnapshot)
            }
        }

        // ⑥ 灌数据（空库门禁；重入已有数据 → 跳过，幂等）。
        var recordsDigest: String?
        if let records = input.records {
            guard records.appID == appID else {
                throw BaseError(code: .validationFailed, message: "重建数据 appID 不符",
                                hint: "records.appID=\(records.appID) ≠ \(appID)")
            }
            let store = try openStore(appID: appID)
            let hasRows = try store.userTableNames().contains { try store.rowCount(in: $0) > 0 }
            store.close()
            if hasRows {
                recordsDigest = try records.digest() // 重入/升级保留数据：跳过灌入（幂等）。
            } else {
                recordsDigest = try applyRecordsExport(records)
            }
        }

        // ⑦ 编译 Card + ⑧ 注册进能力搜索：均为派生（appCard 编译 / base_apps 注册行），
        // applyPackageSnapshot fresh 已建注册行 → 能力搜索面可见。
        _ = try appCard(appID: appID)
        return BaseRebuildResult(appID: appID, rebuilt: !wasComplete,
                                 packageVersion: targetVersion, recordsDigest: recordsDigest)
    }

    /// 幂等写版本记录：已存在同版本且指纹一致 → 跳过（重入）；指纹不一致 → `VERSION_MISMATCH`（内容寻址冲突）。
    public func writePackageVersionIdempotent(_ record: BasePackageVersionRecord) throws {
        try ensurePackageVersionTable(appID: record.snapshot.appID)
        if let existing = try readPackageVersion(appID: record.snapshot.appID, version: record.snapshot.packageVersion) {
            let expected = try record.snapshot.digest()
            let actual = existing["fingerprint"] as? String ?? ""
            guard actual == expected else {
                throw BaseError(code: .versionMismatch, message: "版本记录指纹冲突",
                                hint: "base_pkg_\(record.snapshot.appID) v\(record.snapshot.packageVersion) 已存在且指纹不一致（内容寻址冲突），拒绝覆写")
            }
            return
        }
        try writePackageVersion(appID: record.snapshot.appID, snapshot: record.snapshot, migrations: record.migrations)
    }
}
