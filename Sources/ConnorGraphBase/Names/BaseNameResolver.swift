import Foundation

/// M1-K3：名字解析与子库边界。
///
/// v1 只解析**当前子库表名**（D24：跨库只读导入暂缓，子库间数据面无通路）。
/// - 含点号（全限定 `appID.table` / 跨库形态）→ 拒绝（`TABLE_NOT_IN_SCOPE` 语义，
///   按 M0 契约 11 错误码用 `NOT_FOUND` 承载，收尾报告注明）；
/// - 非法表名 → `VALIDATION_FAILED`；
/// - 合法表名 → 原样返回（供 K2/K4/K5 白名单校验后的 DDL/SQL 拼接）。
///
/// 边界保证：解析结果只在当前 App 子库上下文使用（store 按 appID 物理隔离）；
/// 写越界无任何豁免——跨库写请求在本层即被拒。
public enum BaseNameResolver {

    public static let scopeViolationMessage = "表不在子库作用域内"
    public static let scopeViolationHint = "v1 无跨库数据通路（跨库只读导入暂缓）；需要他 App 数据时请属主提供 exported 只读方法"

    /// 解析表引用。失败抛 `BaseError`。
    public static func resolveTable(_ reference: String, in appID: String) throws -> String {
        if reference.contains(".") {
            throw BaseError(code: .notFound, message: scopeViolationMessage, hint: scopeViolationHint)
        }
        guard BaseSchemaValidator.isValidName(reference) else {
            throw BaseError.validation(.invalidTableName(reference))
        }
        return reference
    }

    /// 解析字段引用：字段名必须合法（供 SQL 拼接白名单）。
    /// 系统主键 `id`（每表隐式 TEXT 主键）始终放行。
    public static func resolveField(_ name: String, in table: String, fields: [String: String]) throws -> String {
        guard BaseSchemaValidator.isValidName(name) else {
            throw BaseError.validation(.invalidFieldName(name))
        }
        if name == "id" {
            return "text"
        }
        guard let type = fields[name] else {
            throw BaseError(code: .notFound, message: "字段不存在", hint: "表 \(table) 不含字段 \(name)")
        }
        return type
    }
}
