import Foundation

/// M3-K1 · 包快照/恢复：在 BaseLibraryStore 上提供「生成快照」与「确定性恢复」。
///
/// 恢复语义：新设备重建（fresh restore）走 createApp 四件套同批；已存在且版本落后时，
/// 原地升级（迁移随包重放、数据保留）由 M3-K6 承担，此处幂等返回或抛 VERSION_MISMATCH。
extension BaseLibraryStore {

    /// 生成 App 的不可变包快照（含 SHA-256 指纹）。
    public func packageSnapshot(appID: String) throws -> BasePackageSnapshot {
        guard let pkg = try packageDictionary(appID: appID) else {
            throw BaseError(code: .notFound, message: "App \(appID) 不存在", hint: "")
        }
        let manifest = pkg["manifest"] as? [String: Any] ?? [:]
        let schema = pkg["schema"] as? [String: Any]
        let methods = pkg["methods"] as? [[String: Any]]
        let guide = pkg["guide"] as? [String: Any] ?? [:]
        let version = (pkg["packageVersion"] as? Int64).map(Int.init) ?? 1
        return BasePackageSnapshot(
            appID: appID,
            packageVersion: version,
            manifest: manifest,
            schema: schema,
            methods: methods,
            guide: guide
        )
    }

    /// 将包快照确定性恢复进注册表。返回恢复后指纹。
    ///
    /// - App 不存在：四件套同批创建（fresh restore）。
    /// - App 已存在且 packageVersion 不落后：幂等返回，不重放。
    /// - App 已存在且版本落后：抛 `VERSION_MISMATCH`（原地升级/迁移重放见 M3-K6）。
    @discardableResult
    public func applyPackageSnapshot(_ snapshot: BasePackageSnapshot) throws -> String {
        let exists = try appExists(snapshot.appID)
        if exists {
            let current = try packageVersion(appID: snapshot.appID)
            if current >= snapshot.packageVersion {
                return try snapshot.digest()
            }
            throw BaseError(
                code: .versionMismatch,
                message: "App \(snapshot.appID) 已存在且版本落后（当前 \(current) < 目标 \(snapshot.packageVersion)），原地升级（迁移重放）由 M3-K6 承担",
                hint: "新设备重建场景请用空注册表恢复"
            )
        }
        // fresh restore：四件套同批创建
        try createApp(
            manifest: snapshot.manifestObject,
            schemaObject: snapshot.schemaObject,
            guide: snapshot.guideObject,
            methods: snapshot.methodsObjects
        )
        // 版本对齐：createApp 置 1，恢复目标版本为快照版本（latest 单调，不倒退）
        try alignPackageVersion(appID: snapshot.appID, to: snapshot.packageVersion)
        return try snapshot.digest()
    }
}
