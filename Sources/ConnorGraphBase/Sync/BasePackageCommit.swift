import Foundation

/// M3-K5 · 包写乐观并发收口：签名级变更统一走「不可变版本记录 + 单调 latest」。
///
/// v0.12 §3.4.2 两类写两种语义：包写（低频结构写）= 不可变版本 + 单调 latest + 乐观并发，
/// 结构变更永不自动合并。M2-M1 已有过期提交返 `VERSION_MISMATCH` 语义，K5 收口为版本记录：
/// 每次签名级变更写一条不可变版本记录（`base_pkg_<appID>` 内容寻址，同版本拒覆写）并单调前移 latest。
extension BaseLibraryStore {

    /// 包写乐观并发提交：生成 next 不可变版本记录并单调前移 latest。
    ///
    /// - `basePackageVersion`：提交依据版本（乐观并发 token），须等于当前 latest，否则 `VERSION_MISMATCH`
    ///   （Agent 拉最新包 rebase 后重提）。
    /// - 以注册库当前四件套（已应用的新结构）生成 next=current+1 快照，写不可变版本记录。
    /// - 单调前移 latest：注册库 `base_apps.package_version`（`alignGuide` 时同步 `guide_version`，防漂移）
    ///   + 子库 `base_pkg_state`（只前移，不回退）。
    /// - 先校验后写：任一步失败即抛，不产生半提交。
    @discardableResult
    public func commitPackageVersion(
        appID: String,
        basePackageVersion: Int,
        migrations: [Int] = [],
        alignGuide: Bool = true
    ) throws -> Int {
        guard try appExists(appID) else {
            throw BaseError.notFound("App \(appID) 不存在")
        }
        let current = try packageVersion(appID: appID)
        guard current == basePackageVersion else {
            throw BaseError(
                code: .versionMismatch,
                message: "包版本过期",
                hint: "当前版本 \(current)，提交基于 \(basePackageVersion)，请拉最新包 rebase 后重提"
            )
        }
        let next = current + 1
        var snapshot = try packageSnapshot(appID: appID)
        snapshot.packageVersion = next
        // 不可变版本记录（内容寻址，同版本拒覆写）。
        try writePackageVersion(appID: appID, snapshot: snapshot, migrations: migrations)
        // 注册库 latest 单调前移（可选 guide_version 对齐）。
        if alignGuide {
            let updated = try registryExecuteVoid("""
                UPDATE base_apps
                SET package_version = ?1, guide_version = ?2, updated_at = ?3
                WHERE app_id = ?4
                """, parameters: [next, next, BaseTime.isoNow(), appID])
            guard updated > 0 else {
                throw BaseError.notFound("App \(appID) 不存在")
            }
        } else {
            let updated = try registryExecuteVoid("""
                UPDATE base_apps
                SET package_version = ?1, updated_at = ?2
                WHERE app_id = ?3
                """, parameters: [next, BaseTime.isoNow(), appID])
            guard updated > 0 else {
                throw BaseError.notFound("App \(appID) 不存在")
            }
        }
        // 子库 latest 单调前移（base_pkg_state，只前移不回退）。
        let store = try openStore(appID: appID)
        defer { store.close() }
        let subLatest = try store.latestPackageVersion()
        if next > subLatest {
            try store.advancePackageVersion(to: next)
        }
        return next
    }
}
