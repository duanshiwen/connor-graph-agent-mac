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

    // MARK: - M1-M7 审计写入

    @Test func auditWritesPerSubLibraryOnToolExecution() async throws {
        let runtime = try makeRuntime()

        let createArgs = #"""
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [
            {"name": "expenses", "fields": [
              {"name": "amount", "type": "number", "required": true, "range": {"min": 0}},
              {"name": "category", "type": "enum", "options": ["餐饮", "交通"]},
              {"name": "note", "type": "text"}
            ]}
          ]},
          "guide": {"whenToUse": "当用户说记一笔且是个人收支时用", "whenNotToUse": "当只是闲聊消费观时不用", "sections": []}
        }
        """#
        var tool = BaseAgentTool(operation: .appCreate, runtime: runtime)
        var result = try await tool.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        let mutateArgs = #"""
        {"appID": "ledger", "table": "expenses", "ops": [{"op": "insert", "record": {"amount": 93, "category": "餐饮", "note": "火锅"}}]}
        """#
        let mutateTool = BaseAgentTool(operation: .recordMutate, runtime: runtime)
        result = try await mutateTool.execute(arguments: try AgentToolArguments(json: mutateArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // 等 execute 末尾 defer 里的审计 Task 落地。
        try await Task.sleep(for: .milliseconds(300))

        let audit = await runtime.readAudit(appID: "ledger")
        #expect(audit.contains { $0["operation"] == "base.app.create" })
        #expect(audit.contains { $0["operation"] == "base.record.mutate" })
        #expect(audit.contains { $0["detail"]?.contains("appID=ledger") == true })
        #expect(audit.contains { $0["detail"]?.contains("table=expenses") == true })

        await runtime.close()
    }

    // MARK: - M2-M1 方法工具（define/invoke/remove + app.update + audit.read）

    @Test func methodDefineInvokeReadOnlyReport() async throws {
        let runtime = try makeRuntime()
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = #"""
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [
            {"name": "expenses", "fields": [
              {"name": "amount", "type": "number", "required": true},
              {"name": "category", "type": "enum", "options": ["餐饮", "交通"]}
            ]}
          ]},
          "guide": {"whenToUse": "当用户说记一笔且是个人收支时用", "whenNotToUse": "当只是闲聊消费观时不用", "sections": []}
        }
        """#
        var result = try await create.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // 定义只读方法：本月餐饮汇总（aggregate + reply，数字必出内核）。
        let defineTool = BaseAgentTool(operation: .methodDefine, runtime: runtime)
        let defineArgs = #"""
        {
          "appID": "ledger",
          "method": {
            "name": "expenses.monthlyTotal",
            "description": "本月支出合计",
            "steps": [
              {"type": "aggregate", "table": "expenses", "aggregations": [{"op": "sum", "field": "amount", "alias": "total"}], "as": "agg"},
              {"type": "reply", "template": {"total": "$agg.0.total"}}
            ],
            "readOnly": true
          },
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}
        }
        """#
        result = try await defineTool.execute(arguments: try AgentToolArguments(json: defineArgs), context: baseToolContext())
        let defEnvelope = try parseEnvelope(result)
        #expect(defEnvelope.ok == true)
        #expect(defEnvelope.data?["method"] as? String == "expenses.monthlyTotal")
        #expect(defEnvelope.data?["readOnly"] as? Bool == true)

        // 写 3 笔后调用方法：total 应出自内核（=485）。
        let mutateTool = BaseAgentTool(operation: .recordMutate, runtime: runtime)
        let mutateArgs = #"""
        {"appID": "ledger", "table": "expenses", "ops": [
          {"op": "insert", "record": {"amount": 120, "category": "餐饮"}},
          {"op": "insert", "record": {"amount": 45, "category": "交通"}},
          {"op": "insert", "record": {"amount": 320, "category": "餐饮"}}
        ]}
        """#
        result = try await mutateTool.execute(arguments: try AgentToolArguments(json: mutateArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        let invokeTool = BaseAgentTool(operation: .methodInvoke, runtime: runtime)
        let invokeArgs = #"""
        {"appID": "ledger", "method": "expenses.monthlyTotal", "input": {}}
        """#
        result = try await invokeTool.execute(arguments: try AgentToolArguments(json: invokeArgs), context: baseToolContext())
        let invokeEnvelope = try parseEnvelope(result)
        #expect(invokeEnvelope.ok == true)
        let inner = invokeEnvelope.data?["data"] as? [String: Any] ?? [:]
        #expect((inner["total"] as? NSNumber)?.doubleValue == 485)
        // 只读方法无写副作用：方法内数据已出内核，无 warn 信号。
        let signals = invokeEnvelope.data?["signals"] as? [[String: Any]] ?? []
        #expect(signals.isEmpty)

        await runtime.close()
    }

    @Test func methodInvokeSurfacesWarnSignalAndRejectsIllegal() async throws {
        let runtime = try makeRuntime()
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = #"""
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [
            {"name": "expenses", "fields": [
              {"name": "amount", "type": "number", "required": true},
              {"name": "category", "type": "enum", "options": ["餐饮", "交通"]}
            ]}
          ]},
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}
        }
        """#
        var result = try await create.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // 定义带 assert warn 的方法：总额 > 100 发超预算信号（事实层不可压）。
        // assert 语义 = 不变量须成立；「不超 100」的不变量是 total <= 100，被违反（total>100）→ warn。
        let defineTool = BaseAgentTool(operation: .methodDefine, runtime: runtime)
        let defineArgs = #"""
        {
          "appID": "ledger",
          "method": {
            "name": "expenses.check",
            "description": "总额检查",
            "steps": [
              {"type": "aggregate", "table": "expenses", "aggregations": [{"op": "sum", "field": "amount", "alias": "total"}], "as": "agg"},
              {"type": "assert", "on": {"path": "$agg.0.total", "op": "lte", "value": 100}, "onFail": "warn", "message": "本月支出超 100 元"},
              {"type": "reply", "template": {"total": "$agg.0.total"}}
            ],
            "readOnly": true
          },
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}
        }
        """#
        result = try await defineTool.execute(arguments: try AgentToolArguments(json: defineArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        let mutateTool = BaseAgentTool(operation: .recordMutate, runtime: runtime)
        result = try await mutateTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "table": "expenses", "ops": [{"op": "insert", "record": {"amount": 360, "category": "餐饮"}}]}"#), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        let invokeTool = BaseAgentTool(operation: .methodInvoke, runtime: runtime)
        result = try await invokeTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "method": "expenses.check", "input": {}}"#), context: baseToolContext())
        let envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        let inner = envelope.data?["data"] as? [String: Any] ?? [:]
        #expect((inner["total"] as? NSNumber)?.doubleValue == 360)
        let signals = envelope.data?["signals"] as? [[String: Any]] ?? []
        #expect(signals.count == 1)
        #expect(signals[0]["level"] as? String == "warn")
        #expect((signals[0]["message"] as? String)?.contains("100") == true)

        await runtime.close()
    }

    @Test func methodRemoveThenInvokeReturnsNotFound() async throws {
        let runtime = try makeRuntime()
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = #"""
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}
        }
        """#
        var result = try await create.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        let defineTool = BaseAgentTool(operation: .methodDefine, runtime: runtime)
        result = try await defineTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "method": {"name": "tmp", "steps": [{"type": "reply", "template": {"ok": true}}]}}"#), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        let removeTool = BaseAgentTool(operation: .methodRemove, runtime: runtime)
        result = try await removeTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "methodName": "tmp"}"#), context: baseToolContext())
        let removeEnvelope = try parseEnvelope(result)
        #expect(removeEnvelope.ok == true)
        #expect(removeEnvelope.data?["removed"] as? String == "tmp")

        let invokeTool = BaseAgentTool(operation: .methodInvoke, runtime: runtime)
        result = try await invokeTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "method": "tmp", "input": {}}"#), context: baseToolContext())
        let envelope = try parseEnvelope(result)
        #expect(envelope.ok == false)
        #expect(envelope.errorCode == "NOT_FOUND")

        await runtime.close()
    }

    @Test func crossAppExportedMethodInvokeViaQualifiedName() async throws {
        let runtime = try makeRuntime()

        // 订阅 App（属主）提供一个 exported 只读方法。
        let subsCreate = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let subsArgs = #"""
        {
          "manifest": {"appID": "subs", "name": "订阅管理", "domain": "订阅", "visibility": "private"},
          "schema": {"tables": [{"name": "subs", "fields": [{"name": "amount", "type": "number"}]}]},
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}
        }
        """#
        var result = try await subsCreate.execute(arguments: try AgentToolArguments(json: subsArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        let defineTool = BaseAgentTool(operation: .methodDefine, runtime: runtime)
        let defineArgs = #"""
        {
          "appID": "subs",
          "method": {
            "name": "summary.monthly",
            "description": "本月订阅待扣总额",
            "steps": [
              {"type": "aggregate", "table": "subs", "aggregations": [{"op": "sum", "field": "amount", "alias": "total"}], "as": "agg"},
              {"type": "reply", "template": {"total": "$agg.0.total"}}
            ],
            "readOnly": true,
            "exports": true
          },
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}
        }
        """#
        result = try await defineTool.execute(arguments: try AgentToolArguments(json: defineArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // 订阅数据：两笔待扣。
        let subsMutate = BaseAgentTool(operation: .recordMutate, runtime: runtime)
        result = try await subsMutate.execute(arguments: try AgentToolArguments(json: #"{"appID": "subs", "table": "subs", "ops": [{"op": "insert", "record": {"amount": 68}}, {"op": "insert", "record": {"amount": 15}}]}"#), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // 记账 App：manifest imports 声明依赖 subs，再跨 App 调用全限定名。
        let ledgerCreate = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let ledgerArgs = #"""
        {
          "manifest": {
            "appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private",
            "requiredCapabilities": ["imports"],
            "imports": [{"appID": "subs", "methods": ["summary.monthly"]}]
          },
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}
        }
        """#
        result = try await ledgerCreate.execute(arguments: try AgentToolArguments(json: ledgerArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        let invokeTool = BaseAgentTool(operation: .methodInvoke, runtime: runtime)
        result = try await invokeTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "method": "subs.summary.monthly", "input": {}}"#), context: baseToolContext())
        let envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        let inner = envelope.data?["data"] as? [String: Any] ?? [:]
        #expect((inner["total"] as? NSNumber)?.doubleValue == 83)
        #expect(envelope.data?["appID"] as? String == "subs")

        await runtime.close()
    }

    @Test func appUpdateOptimisticConcurrency() async throws {
        let runtime = try makeRuntime()
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = #"""
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}
        }
        """#
        var result = try await create.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
        let createEnvelope = try parseEnvelope(result)
        #expect(createEnvelope.ok == true)
        #expect(createEnvelope.data?["packageVersion"] as? Int == 1)

        // 过期版本提交 → VERSION_MISMATCH（rebase 后重提）。
        let updateTool = BaseAgentTool(operation: .appUpdate, runtime: runtime)
        let staleArgs = #"""
        {"appID": "ledger", "basePackageVersion": 1,
         "manifest": {"name": "新名称", "domain": "记账", "visibility": "private"}}
        """#
        // 先推进一版制造过期：建第二张表使 packageVersion=2。
        let tableTool = BaseAgentTool(operation: .tableCreate, runtime: runtime)
        result = try await tableTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "table": {"name": "categories", "fields": [{"name": "name", "type": "text"}]}}"#), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        result = try await updateTool.execute(arguments: try AgentToolArguments(json: staleArgs), context: baseToolContext())
        let staleEnvelope = try parseEnvelope(result)
        #expect(staleEnvelope.ok == false)
        #expect(staleEnvelope.errorCode == "VERSION_MISMATCH")

        // 以最新版本提交 → 成功，packageVersion 单调前移。
        let freshArgs = #"""
        {"appID": "ledger", "basePackageVersion": 2,
         "manifest": {"name": "新名称", "domain": "记账", "visibility": "private"}}
        """#
        result = try await updateTool.execute(arguments: try AgentToolArguments(json: freshArgs), context: baseToolContext())
        let freshEnvelope = try parseEnvelope(result)
        #expect(freshEnvelope.ok == true)
        #expect(freshEnvelope.data?["packageVersion"] as? Int == 3)

        await runtime.close()
    }

    @Test func auditReadReturnsPerSubLibraryRows() async throws {
        let runtime = try makeRuntime()
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = #"""
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}
        }
        """#
        var result = try await create.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        let mutateTool = BaseAgentTool(operation: .recordMutate, runtime: runtime)
        result = try await mutateTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "table": "expenses", "ops": [{"op": "insert", "record": {"amount": 93}}]}"#), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)
        try await Task.sleep(for: .milliseconds(300))

        let auditTool = BaseAgentTool(operation: .auditRead, runtime: runtime)
        result = try await auditTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger"}"#), context: baseToolContext())
        let envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        let rows = envelope.data?["rows"] as? [[String: Any]] ?? []
        #expect(rows.count >= 2)
        #expect(rows.contains { ($0["operation"] as? String) == "base.app.create" })
        #expect(rows.contains { ($0["operation"] as? String) == "base.record.mutate" })

        await runtime.close()
    }

    @Test func guideDriftBlocksInvokeUntilSynced() async throws {
        let runtime = try makeRuntime()
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        var result = try await create.execute(arguments: try AgentToolArguments(json: #"""
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}
        }
        """#), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // 签名级变更 method.define 未同批改指南 → 指南漂移。
        let defineTool = BaseAgentTool(operation: .methodDefine, runtime: runtime)
        result = try await defineTool.execute(arguments: try AgentToolArguments(json: #"""
        {
          "appID": "ledger",
          "method": {"name": "expenses.total", "steps": [
            {"type": "aggregate", "table": "expenses", "aggregations": [{"op": "sum", "field": "amount", "alias": "total"}], "as": "agg"},
            {"type": "reply", "template": {"total": "$agg.0.total"}}
          ], "readOnly": true}
        }
        """#), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // invoke 被漂移检测拒：GUIDE_OUT_OF_SYNC（不能按过期指南调用）。
        let invokeTool = BaseAgentTool(operation: .methodInvoke, runtime: runtime)
        result = try await invokeTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "method": "expenses.total", "input": {}}"#), context: baseToolContext())
        let driftEnvelope = try parseEnvelope(result)
        #expect(driftEnvelope.ok == false)
        #expect(driftEnvelope.errorCode == "GUIDE_OUT_OF_SYNC")

        // 用 base.app.update 同批同步指南后，invoke 恢复可用。
        let updateTool = BaseAgentTool(operation: .appUpdate, runtime: runtime)
        result = try await updateTool.execute(arguments: try AgentToolArguments(json: #"""
        {
          "appID": "ledger", "basePackageVersion": 2,
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": [], "methods": ["expenses.total"]}
        }
        """#), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        result = try await invokeTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "method": "expenses.total", "input": {}}"#), context: baseToolContext())
        let syncedEnvelope = try parseEnvelope(result)
        #expect(syncedEnvelope.ok == true)

        await runtime.close()
    }

    @Test func appUpdateWithSchemaWithoutGuideRejectsGuideOutOfSync() async throws {
        let runtime = try makeRuntime()
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        var result = try await create.execute(arguments: try AgentToolArguments(json: #"""
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}
        }
        """#), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // app.update 带 schema 变更但未同批带 guide → GUIDE_OUT_OF_SYNC。
        let updateTool = BaseAgentTool(operation: .appUpdate, runtime: runtime)
        result = try await updateTool.execute(arguments: try AgentToolArguments(json: #"""
        {
          "appID": "ledger", "basePackageVersion": 1,
          "schema": {"tables": [
            {"name": "expenses", "fields": [{"name": "amount", "type": "number"}]},
            {"name": "categories", "fields": [{"name": "name", "type": "text"}]}
          ]}
        }
        """#), context: baseToolContext())
        let envelope = try parseEnvelope(result)
        #expect(envelope.ok == false)
        #expect(envelope.errorCode == "GUIDE_OUT_OF_SYNC")

        await runtime.close()
    }

    @Test func syncGuideViaAppUpdateClearsDriftAndCardShowsFlag() async throws {
        let runtime = try makeRuntime()
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        var result = try await create.execute(arguments: try AgentToolArguments(json: #"""
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}
        }
        """#), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // 签名级变更：建第二张表（table.create），指南未同步 → 漂移。
        let tableTool = BaseAgentTool(operation: .tableCreate, runtime: runtime)
        result = try await tableTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "table": {"name": "categories", "fields": [{"name": "name", "type": "text"}]}}"#), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)
        #expect(try await runtime.isGuideOutOfSync(appID: "ledger") == true)

        // app.update 同批带 guide 同步 → 漂移消除。
        let updateTool = BaseAgentTool(operation: .appUpdate, runtime: runtime)
        result = try await updateTool.execute(arguments: try AgentToolArguments(json: #"""
        {
          "appID": "ledger", "basePackageVersion": 2,
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": [], "tables": ["expenses", "categories"]}
        }
        """#), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)
        #expect(try await runtime.isGuideOutOfSync(appID: "ledger") == false)

        // Card 暴露 guideOutOfSync 标志。
        let getTool = BaseAgentTool(operation: .appGet, runtime: runtime)
        result = try await getTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger"}"#), context: baseToolContext())
        let getEnvelope = try parseEnvelope(result)
        #expect(getEnvelope.ok == true)
        #expect(getEnvelope.data?["guideOutOfSync"] as? Bool == false)

        await runtime.close()
    }

    // MARK: - M2-M4 只读报表方法纵切（记账月度报表）

    /// 报表 = 只读方法（v0.12 §2.4）：多聚合 + 趋势对比 + 预算超线 warn + reply 组合，数字必出内核。
    /// 方法体内无算术算子——reply 只做 JSONPath 替换；趋势/信号均出自内核返回。
    @Test func bookkeepingMonthlyReportReadOnlyVerticalSlice() async throws {
        let runtime = try makeRuntime()

        // 1) 建正式私有记账 App（四件套同批，manifest 带一句话用途）。
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = #"""
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private", "purpose": "记录个人收支、按月给预算"},
          "schema": {"tables": [
            {"name": "expenses", "fields": [
              {"name": "amount", "type": "number", "required": true, "range": {"min": 0}},
              {"name": "category", "type": "enum", "options": ["餐饮", "交通"]},
              {"name": "month", "type": "enum", "options": ["2026-08", "2026-09"]},
              {"name": "paid", "type": "boolean", "default": false}
            ]}
          ]},
          "guide": {"whenToUse": "当用户说记一笔且是个人收支时用", "whenNotToUse": "当只是闲聊消费观时不用", "sections": []}
        }
        """#
        var result = try await create.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // 2) 写 5 笔（本月 3 笔共 485，上月 2 笔共 260）。
        let mutate = BaseAgentTool(operation: .recordMutate, runtime: runtime)
        let mutateArgs = #"""
        {"appID": "ledger", "table": "expenses", "ops": [
          {"op": "insert", "record": {"amount": 320, "category": "餐饮", "month": "2026-09", "paid": true}},
          {"op": "insert", "record": {"amount": 45, "category": "交通", "month": "2026-09", "paid": true}},
          {"op": "insert", "record": {"amount": 120, "category": "餐饮", "month": "2026-09", "paid": false}},
          {"op": "insert", "record": {"amount": 200, "category": "餐饮", "month": "2026-08", "paid": true}},
          {"op": "insert", "record": {"amount": 60, "category": "交通", "month": "2026-08", "paid": true}}
        ]}
        """#
        result = try await mutate.execute(arguments: try AgentToolArguments(json: mutateArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // 3) 定义只读月度报表方法：本月 sum+count、上月 sum、预算超线 warn、reply 组合。
        let define = BaseAgentTool(operation: .methodDefine, runtime: runtime)
        let defineArgs = #"""
        {
          "appID": "ledger",
          "method": {
            "name": "expenses.monthlyReport",
            "description": "月度支出报表：本月合计/笔数 + 对比上月 + 预算超线 warn",
            "steps": [
              {"type": "aggregate", "table": "expenses", "filter": {"and": [{"field": "month", "op": "in", "value": ["2026-09"]}]},
               "aggregations": [{"op": "sum", "field": "amount", "alias": "total"}, {"op": "count", "field": "id", "alias": "count"}], "as": "cur"},
              {"type": "aggregate", "table": "expenses", "filter": {"and": [{"field": "month", "op": "in", "value": ["2026-08"]}]},
               "aggregations": [{"op": "sum", "field": "amount", "alias": "total"}], "as": "prev"},
              {"type": "assert", "on": {"path": "$cur.0.total", "op": "lte", "value": 450}, "onFail": "warn", "message": "本月支出超预算线 450"},
              {"type": "reply", "template": {"month": "2026-09", "total": "$cur.0.total", "count": "$cur.0.count", "prevTotal": "$prev.0.total"}}
            ],
            "readOnly": true
          },
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}
        }
        """#
        result = try await define.execute(arguments: try AgentToolArguments(json: defineArgs), context: baseToolContext())
        let defEnvelope = try parseEnvelope(result)
        #expect(defEnvelope.ok == true)
        #expect(defEnvelope.data?["readOnly"] as? Bool == true)

        // 4) 调用报表方法：数字必出内核（total=485、count=3、prevTotal=260），预算超线 warn 必现（事实层不可压）。
        let invoke = BaseAgentTool(operation: .methodInvoke, runtime: runtime)
        result = try await invoke.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "method": "expenses.monthlyReport", "input": {}}"#), context: baseToolContext())
        let envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        let inner = envelope.data?["data"] as? [String: Any] ?? [:]
        #expect((inner["total"] as? NSNumber)?.doubleValue == 485)
        #expect((inner["count"] as? NSNumber)?.doubleValue == 3)
        #expect((inner["prevTotal"] as? NSNumber)?.doubleValue == 260)
        let signals = envelope.data?["signals"] as? [[String: Any]] ?? []
        #expect(signals.count == 1)
        #expect(signals[0]["level"] as? String == "warn")
        #expect((signals[0]["message"] as? String)?.contains("超预算线 450") == true)

        // 5) 报表方法进入 App Card 方法摘要（catalog「解锁你没用过的方法」）：只读方法可发现。
        let get = BaseAgentTool(operation: .appGet, runtime: runtime)
        result = try await get.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger"}"#), context: baseToolContext())
        let getEnvelope = try parseEnvelope(result)
        #expect(getEnvelope.ok == true)
        let methods = getEnvelope.data?["methods"] as? [[String: Any]] ?? []
        let report = try #require(methods.first { ($0["name"] as? String) == "expenses.monthlyReport" })
        #expect(report["readOnly"] as? Bool == true)
        #expect(report["description"] as? String != nil)

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
