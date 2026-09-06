import XCTest
@testable import ConnorGraphBase

/// 契约快照测试（M0-6）：三端加载同一份 base.sdk.v1.json 并断言关键契约事实。
/// 断言口径与后端 service/base/contract_test.go、Android ContractSnapshotTest 一致。
final class ContractSnapshotTests: XCTestCase {

    // MARK: - 工具目录

    func testToolsExactly25() throws {
        let tools = try sdkDict()["tools"] as? [[String: Any]] ?? []
        XCTAssertEqual(tools.count, 25, "工具面冻结 25 个（施工图 v1.5 附录 A）")
        var seen = Set<String>()
        for tool in tools {
            let name = tool["name"] as? String ?? ""
            XCTAssertFalse(name.isEmpty, "工具缺 name")
            XCTAssertFalse(seen.contains(name), "工具名重复: \(name)")
            seen.insert(name)
        }
        for required in Self.requiredTools {
            XCTAssertTrue(seen.contains(required), "缺工具: \(required)")
        }
    }

    // MARK: - 错误码

    func testErrorCodeTaxonomy() throws {
        let dict = try sdkDict()
        let errorCodes = dict["errorCodes"] as? [String: Any] ?? [:]
        XCTAssertEqual(errorCodes["taxonomyRows"] as? Int, 10, "taxonomy 10 行")
        let codes = errorCodes["codes"] as? [[String: Any]] ?? []
        XCTAssertEqual(codes.count, 11, "末行含 RATE_LIMITED/INTERNAL 两 code")
        var seen = Set<String>()
        for code in codes {
            let c = code["code"] as? String ?? ""
            XCTAssertFalse(c.isEmpty)
            XCTAssertFalse(seen.contains(c), "错误码重复: \(c)")
            seen.insert(c)
            XCTAssertNotNil(code["retryable"] as? Bool, "错误码 \(c) 缺 retryable")
        }
        for required in Self.requiredErrorCodes {
            XCTAssertTrue(seen.contains(required), "缺错误码: \(required)")
        }
    }

    // MARK: - 结构化查询操作符

    func testQueryOperatorsByType() throws {
        let dict = try sdkDict()
        let query = dict["query"] as? [String: Any] ?? [:]
        let filter = query["filter"] as? [String: Any] ?? [:]
        let ops = filter["operatorsByType"] as? [String: Any] ?? [:]
        let want: [String: [String]] = [
            "text": ["eq", "contains", "startsWith", "in"],
            "number": ["eq", "gt", "gte", "lt", "lte", "between"],
            "date": ["on", "before", "after", "range"],
            "enum": ["in"],
            "relation": ["has", "lookup"],
        ]
        for (type, expected) in want {
            let got = ops[type] as? [String] ?? []
            XCTAssertEqual(got, expected, "\(type) 操作符")
        }
        let aggregateOps = query["aggregateOps"] as? [String] ?? []
        XCTAssertEqual(aggregateOps.count, 5, "聚合算子 5 个")
    }

    // MARK: - 应用取舍决策段（v0.9/v0.12）

    func testAppDecisionNoIntermediateState() throws {
        let dict = try sdkDict()
        let decision = dict["appDecision"] as? [String: Any] ?? [:]
        XCTAssertEqual((decision["threeQuestions"] as? [Any])?.count, 3, "三问路由")
        XCTAssertEqual((decision["fourActions"] as? [Any])?.count, 4, "用/改/装/建")
        XCTAssertGreaterThanOrEqual((decision["antiPatterns"] as? [Any])?.count ?? 0, 6, "反模式禁令")
        let no = decision["noIntermediateState"] as? String ?? ""
        for must in ["不设任何中间态", "无个人工作台", "无散表", "转正", "正式私有小应用", "base.app.create", "非结构化记忆"] {
            XCTAssertTrue(no.contains(must), "决策段缺口径: \(must)")
        }
        let questions = decision["threeQuestions"] as? [String] ?? []
        let joined = questions.joined()
        for frag in ["重复写入", "统计", "代价"] {
            XCTAssertTrue(joined.contains(frag), "三问判据缺 \(frag)")
        }
    }

    // MARK: - 交互富集规范段（v0.10）

    func testEnrichmentSection() throws {
        let dict = try sdkDict()
        let enrichment = dict["enrichment"] as? [String: Any] ?? [:]
        let text = [
            enrichment["accompanyingRead"] as? String ?? "",
            enrichment["factBeforeStance"] as? String ?? "",
            enrichment["warnMandatory"] as? String ?? "",
            enrichment["restraint"] as? String ?? "",
            (enrichment["replyShape"] as? [String])?.joined() ?? "",
        ].joined()
        for must in ["伴随读取", "事实先行", "不心算", "不得压下", "操作回执", "2–4", "增量"] {
            XCTAssertTrue(text.contains(must), "富集段缺口径: \(must)")
        }
    }

    // MARK: - 能力点清单（v0.11 跨库单路径）

    func testCapabilitiesDeferredImport() throws {
        let dict = try sdkDict()
        let capabilities = dict["capabilities"] as? [String: Any] ?? [:]
        let grantedNames = (capabilities["v1Granted"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        for required in ["imports", "network", "asset"] {
            XCTAssertTrue(grantedNames.contains(required), "v1 缺能力点: \(required)")
        }
        let deferred = capabilities["deferred"] as? [[String: Any]] ?? []
        let importEntry = deferred.first { ($0["name"] as? String) == "import" }
        XCTAssertNotNil(importEntry, "缺 import deferred 条目")
        XCTAssertEqual(importEntry?["deferred"] as? Bool, true, "import 必须标 deferred")
        let policy = ((importEntry?["reason"] as? String) ?? "") + " " + ((importEntry?["crossAppPolicy"] as? String) ?? "")
        for must in ["exported", "v1 不发放", "跨库"] {
            XCTAssertTrue(policy.contains(must), "跨库单路径口径缺 \(must)")
        }
    }

    // MARK: - 指南模板（app-package.schema.json）

    func testGuideTemplateNoWorkbench() throws {
        let text = try schemaText()
        for must in ["不设任何中间态", "无个人工作台", "无散表", "正式私有小应用", "base.app.create", "伴随读取", "事实先行"] {
            XCTAssertTrue(text.contains(must), "指南模板缺口径: \(must)")
        }
    }

    // MARK: - 工具函数

    private func sdkDict() throws -> [String: Any] {
        try SDKContractLoader.load(.sdk)
    }

    private func schemaText() throws -> String {
        let data = try SDKContractLoader.loadData(.appPackage)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static let requiredTools = [
        "base.guide", "base.app.create", "base.app.delete", "base.app.list", "base.app.get",
        "base.table.create", "base.table.alter", "base.record.get", "base.query.select",
        "base.query.aggregate", "base.record.mutate", "base.import.csv", "base.export.csv",
        "base.app.update", "base.method.define", "base.method.invoke", "base.method.remove",
        "base.audit.read", "base.sync.status", "base.app.grant", "base.asset.upload",
        "base.publish", "base.share", "base.unpublish", "base.acl.set",
    ]

    private static let requiredErrorCodes = [
        "VALIDATION_FAILED", "NOT_FOUND", "PERMISSION_DENIED", "CAPABILITY_REQUIRED",
        "GUIDE_OUT_OF_SYNC", "VERSION_MISMATCH", "MIGRATION_FAILED", "CONFLICT",
        "QUOTA_EXCEEDED", "RATE_LIMITED", "INTERNAL",
    ]
}
