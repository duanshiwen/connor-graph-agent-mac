import Foundation

/// M3-K1 · 包快照/恢复：在 BaseLibraryStore 上提供「生成快照」与「确定性恢复」。
///
/// 恢复语义：新设备重建（fresh restore）走 createApp 四件套同批；已存在且不落后时幂等返回；
/// 已存在且版本落后时由 M3-K6 原地升级（迁移随包确定性重放、数据保留），
/// 失败 `MIGRATION_FAILED` 停留旧版（版本链缺失同样无法重放）。
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
    /// - App 已存在且版本落后：M3-K6 原地升级——按版本记录链确定性重放迁移（数据保留），
    ///   失败 `MIGRATION_FAILED` 停留旧版；版本链缺失同样无法重放。
    @discardableResult
    public func applyPackageSnapshot(_ snapshot: BasePackageSnapshot) throws -> String {
        let exists = try appExists(snapshot.appID)
        if exists {
            let current = try packageVersion(appID: snapshot.appID)
            if current >= snapshot.packageVersion {
                return try snapshot.digest()
            }
            // M3-K6：原地升级（迁移随包确定性重放，数据保留）。
            _ = try upgradePackageSnapshot(snapshot)
            return try snapshot.digest()
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
