import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

/// M1-M3：13 工具薄封装的冒烟验证（工具注册 + 记账端到端 + 能力点门禁 + dryRun）。
@Suite struct BaseAgentToolsTests {

    // MARK: - 工具注册

    @Test func registerBaseToolsRegistersAll13Tools() async throws {
        let runtime = try makeRuntime()
        var registry = AgentToolRegistry()
        registry.registerBaseTools(runtime: runtime)

        let names = [
            "base.guide", "base.app.create", "base.app.delete", "base.app.list", "base.app.get",
            "base.table.create", "base.table.alter", "base.record.get", "base.query.select",
            "base.query.aggregate", "base.record.mutate", "base.import.csv", "base.export.csv"
        ]
        for name in names {
            #expect(registry.definition(named: name) != nil, "缺少工具 \(name)")
        }
        #expect(registry.definitions.count >= names.count)
    }

    // MARK: - 记账端到端

    @Test func bookkeepingFlowCreateTableMutateAggregateExport() async throws {
        let runtime = try makeRuntime()
        let tool = BaseAgentTool(operation: .appCreate, runtime: runtime)

        // 1) 建正式私有记账 App（四件套同批）。
        let createArgs = #"""
        {
          "manifest": {
            "appID": "ledger",
            "name": "记账本",
            "domain": "记账",
            "visibility": "private"
          },
          "schema": {
            "tables": [
              {
                "name": "expenses",
                "fields": [
                  {"name": "amount", "type": "number", "required": true},
                  {"name": "category", "type": "enum", "options": ["餐饮", "交通", "购物"]},
                  {"name": "note", "type": "text"}
                ]
              }
            ]
          },
          "guide": {
            "whenToUse": "当用户说记一笔且是个人收支时用",
            "whenNotToUse": "当只是闲聊消费观时不用",
            "sections": [
              {"title": "是什么", "body": "个人记账小应用"},
              {"title": "方法", "body": "直调 base.* 原子工具"}
            ]
          }
        }
        """#
        var result = try await tool.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
        let createEnvelope = try parseEnvelope(result)
        #expect(createEnvelope.ok == true)
        #expect(createEnvelope.data?["appID"] as? String == "ledger")
        #expect(createEnvelope.data?["packageVersion"] as? Int == 1)

        // 2) 追加第二张表（签名级变更，packageVersion 前移到 2）。
        let tableCreateArgs = #"""
        {"appID": "ledger", "table": {"name": "categories", "fields": [{"name": "name", "type": "text"}]}}
        """#
        var tableTool = BaseAgentTool(operation: .tableCreate, runtime: runtime)
        result = try await tableTool.execute(arguments: try AgentToolArguments(json: tableCreateArgs), context: baseToolContext())
        var envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        #expect(envelope.data?["table"] as? String == "categories")
        #expect(envelope.data?["packageVersion"] as? Int == 2)

        // 3) 写入 3 笔支出。
        let mutateArgs = #"""
        {
          "appID": "ledger",
          "table": "expenses",
          "ops": [
            {"op": "insert", "record": {"amount": 120, "category": "餐饮", "note": "午饭"}},
            {"op": "insert", "record": {"amount": 45, "category": "交通", "note": "地铁"}},
            {"op": "insert", "record": {"amount": 320, "category": "餐饮", "note": "聚餐"}}
          ]
        }
        """#
        var mutateTool = BaseAgentTool(operation: .recordMutate, runtime: runtime)
        result = try await mutateTool.execute(arguments: try AgentToolArguments(json: mutateArgs), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        #expect(envelope.data?["affected"] as? Int == 3)

        // 4) 聚合：本月累计（数字必出内核）。
        let aggregateArgs = #"""
        {"appID": "ledger", "table": "expenses", "aggregations": [{"op": "sum", "field": "amount", "alias": "total"}]}
        """#
        var aggregateTool = BaseAgentTool(operation: .queryAggregate, runtime: runtime)
        result = try await aggregateTool.execute(arguments: try AgentToolArguments(json: aggregateArgs), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        let rows = envelope.data?["rows"] as? [[String: Any]] ?? []
        #expect(rows.count == 1)
        #expect((rows[0]["total"] as? NSNumber)?.doubleValue == 485)

        // 5) 分组聚合（按类别）。
        let groupArgs = #"""
        {"appID": "ledger", "table": "expenses", "aggregations": [{"op": "sum", "field": "amount", "alias": "total"}], "groupBy": ["category"]}
        """#
        aggregateTool = BaseAgentTool(operation: .queryAggregate, runtime: runtime)
        result = try await aggregateTool.execute(arguments: try AgentToolArguments(json: groupArgs), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        let grouped = envelope.data?["rows"] as? [[String: Any]] ?? []
        let categoryTotals: [String: Double] = Dictionary(uniqueKeysWithValues: grouped.compactMap { row -> (String, Double)? in
            guard let category = row["category"] as? String,
                  let total = (row["total"] as? NSNumber)?.doubleValue else { return nil }
            return (category, total)
        })
        #expect(categoryTotals["餐饮"] == 440)
        #expect(categoryTotals["交通"] == 45)

        // 6) 结构化查询过滤。
        let selectArgs = #"""
        {"appID": "ledger", "table": "expenses", "filter": {"and": [{"field": "category", "op": "in", "value": ["餐饮"]}]}}
        """#
        var selectTool = BaseAgentTool(operation: .querySelect, runtime: runtime)
        result = try await selectTool.execute(arguments: try AgentToolArguments(json: selectArgs), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        #expect((envelope.data?["rows"] as? [[String: Any]])?.count == 2)

        // 7) 导出 CSV（外部文件通道）。
        let exportArgs = #"{"appID": "ledger", "table": "expenses"}"#
        var exportTool = BaseAgentTool(operation: .exportCSV, runtime: runtime)
        result = try await exportTool.execute(arguments: try AgentToolArguments(json: exportArgs), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        let csv = envelope.data?["csv"] as? String ?? ""
        #expect(csv.contains("amount,category,note"))
        #expect(csv.contains("320"))

        // 8) dryRun 导入不落库（走 mutate 校验路径）。
        let importArgs = #"""
        {"appID": "ledger", "table": "expenses", "dryRun": true,
          "rows": [{"amount": 88, "category": "购物", "note": "dry"}]}
        """#
        var importTool = BaseAgentTool(operation: .importCSV, runtime: runtime)
        result = try await importTool.execute(arguments: try AgentToolArguments(json: importArgs), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        #expect(envelope.data?["dryRun"] as? Bool == true)
        #expect(envelope.data?["imported"] as? Int == 1)

        // 9) dryRun 后记录数不变。
        selectTool = BaseAgentTool(operation: .querySelect, runtime: runtime)
        result = try await selectTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "table": "expenses"}"#), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect((envelope.data?["rows"] as? [[String: Any]])?.count == 3)

        await runtime.close()
    }

    // MARK: - 能力点门禁

    @Test func appCreateRejectsDeferredImportCapability() async throws {
        let runtime = try makeRuntime()
        let tool = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let args = #"""
        {
          "manifest": {
            "appID": "badapp", "name": "坏应用", "domain": "测试", "visibility": "private",
            "requiredCapabilities": ["import"]
          },
          "schema": {"tables": [{"name": "t", "fields": [{"name": "a", "type": "text"}]}]},
          "guide": {"whenToUse": "x", "whenNotToUse": "y"}
        }
        """#
        let result = try await tool.execute(arguments: try AgentToolArguments(json: args), context: baseToolContext())
        let envelope = try parseEnvelope(result)
        #expect(envelope.ok == false)
        #expect(envelope.errorCode == "CAPABILITY_REQUIRED")
        await runtime.close()
    }

    // MARK: - 契约

    @Test func guideReturnsContractText() async throws {
        let runtime = try makeRuntime()
        let tool = BaseAgentTool(operation: .guide, runtime: runtime)
        let result = try await tool.execute(arguments: try AgentToolArguments(json: #"{}"#), context: baseToolContext())
        let envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        let content = envelope.data?["content"] as? String ?? ""
        #expect(content.contains("base.record.mutate"))
        await runtime.close()
    }

    // MARK: - M1-M6 记账场景纵切

    @Test func bookkeepingVerticalSliceMonthlyAggregateAndErrorPaths() async throws {
        let runtime = try makeRuntime()

        // 建正式私有记账 App（四件套同批）。
        let createArgs = #"""
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [
            {"name": "expenses", "fields": [
              {"name": "amount", "type": "number", "required": true, "range": {"min": 0}},
              {"name": "category", "type": "enum", "options": ["餐饮", "交通", "购物"]},
              {"name": "note", "type": "text"}
            ]}
          ]},
          "guide": {"whenToUse": "当用户说记一笔且是个人收支时用", "whenNotToUse": "当只是闲聊消费观时不用", "sections": []}
        }
        """#
        var tool = BaseAgentTool(operation: .appCreate, runtime: runtime)
        var result = try await tool.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
        var envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)

        // “记一笔火锅 93” → mutate insert（含一笔交通、一笔咖啡）。
        var mutateTool = BaseAgentTool(operation: .recordMutate, runtime: runtime)
        let insertArgs = #"""
        {"appID": "ledger", "table": "expenses", "ops": [
          {"op": "insert", "record": {"amount": 93, "category": "餐饮", "note": "火锅"}},
          {"op": "insert", "record": {"amount": 35, "category": "交通", "note": "地铁"}},
          {"op": "insert", "record": {"amount": 68, "category": "餐饮", "note": "咖啡"}}
        ]}
        """#
        result = try await mutateTool.execute(arguments: try AgentToolArguments(json: insertArgs), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        #expect(envelope.data?["affected"] as? Int == 3)

        // “本月餐饮花了多少” → aggregate sum(amount) where category in [餐饮]（数字必出内核）。
        var aggTool = BaseAgentTool(operation: .queryAggregate, runtime: runtime)
        let aggArgs = #"""
        {"appID": "ledger", "table": "expenses", "aggregations": [{"op": "sum", "field": "amount", "alias": "total"}],
         "filter": {"and": [{"field": "category", "op": "in", "value": ["餐饮"]}]}}
        """#
        result = try await aggTool.execute(arguments: try AgentToolArguments(json: aggArgs), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        let rows = envelope.data?["rows"] as? [[String: Any]] ?? []
        #expect((rows.first?["total"] as? NSNumber)?.doubleValue == 161)

        // 缺金额 → VALIDATION_FAILED + hint 含 amount（缺参纠错）。
        let missingAmountArgs = #"""
        {"appID": "ledger", "table": "expenses", "ops": [{"op": "insert", "record": {"category": "餐饮", "note": "缺金额"}}]}
        """#
        result = try await mutateTool.execute(arguments: try AgentToolArguments(json: missingAmountArgs), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == false)
        #expect(envelope.errorCode == "VALIDATION_FAILED")
        #expect(envelope.errorHint?.contains("amount") == true)

        // 越界 → 负金额被 schema range 拒绝（VALIDATION_FAILED）。
        let negativeArgs = #"""
        {"appID": "ledger", "table": "expenses", "ops": [{"op": "insert", "record": {"amount": -50, "category": "餐饮"}}]}
        """#
        result = try await mutateTool.execute(arguments: try AgentToolArguments(json: negativeArgs), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == false)
        #expect(envelope.errorCode == "VALIDATION_FAILED")

        await runtime.close()
    }

    // MARK: - Helpers

    private func makeRuntime() throws -> BaseToolRuntime {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-tools-\(UUID().uuidString)", isDirectory: true)
        return try BaseToolRuntime(directory: directory)
    }

    private func baseToolContext() -> AgentToolExecutionContext {
        AgentToolExecutionContext(
            runID: "run-base-tools",
            sessionID: "session",
            groupID: "group",
            userPrompt: "base tools test",
            toolCallID: UUID().uuidString,
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    }

    private struct EnvelopeBox {
        var ok: Bool
        var data: [String: Any]?
        var errorCode: String?
        var errorHint: String?
    }

    private func parseEnvelope(_ result: AgentToolResult) throws -> EnvelopeBox {
        let json = try #require(result.contentJSON)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let ok = object["ok"] as? Bool ?? false
        let data = object["data"] as? [String: Any]
        let error = object["error"] as? [String: Any]
        return EnvelopeBox(ok: ok, data: data, errorCode: error?["code"] as? String, errorHint: error?["hint"] as? String)
    }
}
