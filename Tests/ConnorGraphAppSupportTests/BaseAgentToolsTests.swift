import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

/// M1-M7 工具层验证（M7 双面硬切口径）：
/// - 运行面目录恰为 4 工具（method.invoke / app.list / app.get / guide），制作面按面增删；
/// - authoring 工具受 execute() 硬门禁约束：仅制作面会话内可执行（属主不豁免）；
/// - guide 双态（authoring + usage）+ 制作面解锁/退回使用面状态机；
/// - export.csv 步骤、method.step 步骤审计与 traceId 贯穿；
/// - 所有 base.* 工具调用免用户审批（任何权限模式，含 readOnly）。
@Suite struct BaseAgentToolsTests {

    // MARK: - 工具注册

    /// M7 双面投影：默认（运行面）目录恰为 4 个 base.* 工具——method.invoke / app.list /
    /// app.get / guide；authoring 面工具不进默认目录。
    @Test func registerBaseToolsProjectsRuntimeCatalogOf4Tools() async throws {
        let runtime = try makeRuntime()
        var registry = AgentToolRegistry()
        registry.registerBaseTools(runtime: runtime)

        let names = [
            "base.method.invoke", "base.app.list", "base.app.get", "base.guide"
        ]
        for name in names {
            #expect(registry.definition(named: name) != nil, "缺少运行面工具 \(name)")
        }
        #expect(registry.definitions.count == names.count, "运行面目录应恰为 4 个 base 工具")
        // authoring 面工具不得出现在运行面目录。
        for operation in BaseAgentTool.Operation.allCases where operation.surface == .authoring {
            #expect(registry.definition(named: operation.rawValue) == nil,
                    "authoring 工具 \(operation.rawValue) 不得进运行面目录")
        }
    }

    /// M7 制作面投影：registerBaseAuthoringTools 补挂全部 authoring 工具；
    /// unregisterBaseAuthoringTools 收回后目录回到运行面 4 工具。
    @Test func authoringToolsProjectAndUnproject() async throws {
        let runtime = try makeRuntime()
        var registry = AgentToolRegistry()
        registry.registerBaseTools(runtime: runtime)
        registry.registerBaseAuthoringTools(runtime: runtime)

        let authoringOps = BaseAgentTool.Operation.allCases.filter { $0.surface == .authoring }
        #expect(authoringOps.count == 14)
        for operation in authoringOps {
            #expect(registry.definition(named: operation.rawValue) != nil,
                    "制作面工具 \(operation.rawValue) 应已补挂")
        }

        #expect(registry.unregisterBaseAuthoringTools() == true)
        for operation in authoringOps {
            #expect(registry.definition(named: operation.rawValue) == nil,
                    "收回后 \(operation.rawValue) 不应残留")
        }
        #expect(registry.definitions.count == 4, "收回后目录应回到运行面 4 工具")
    }

    // MARK: - 记账端到端

    @Test func bookkeepingFlowCreateTableMutateAggregateExport() async throws {
        let runtime = try makeRuntime()
        let tool = BaseAgentTool(operation: .appCreate, runtime: runtime)

        // 属主进入制作面（本机建 App 前先置制作面态）。
        await runtime.enterAuthoring(appID: "ledger")

        // 1) 建正式私有记账 App（四件套同批，guide 双态）。
        let createArgs = """
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
          \(Self.dualGuide)
        }
        """
        var result = try await tool.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
        let createEnvelope = try parseEnvelope(result)
        #expect(createEnvelope.ok == true)
        #expect(createEnvelope.data?["appID"] as? String == "ledger")
        #expect(createEnvelope.data?["packageVersion"] as? Int == 1)

        // 2) 追加第二张表（签名级变更，packageVersion 前移到 2）。
        let tableCreateArgs = #"""
        {"appID": "ledger", "table": {"name": "categories", "fields": [{"name": "name", "type": "text"}]}}
        """#
        let tableTool = BaseAgentTool(operation: .tableCreate, runtime: runtime)
        result = try await tableTool.execute(arguments: try AgentToolArguments(json: tableCreateArgs), context: baseToolContext())
        var envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        #expect(envelope.data?["table"] as? String == "categories")
        #expect(envelope.data?["packageVersion"] as? Int == 2)

        // 3) 写入 3 笔支出。
        let mutateArgs = """
        {
          "appID": "ledger",
          "table": "expenses",
          "ops": [
            {"op": "insert", "record": {"amount": 120, "category": "餐饮", "note": "午饭"}},
            {"op": "insert", "record": {"amount": 45, "category": "交通", "note": "地铁"}},
            {"op": "insert", "record": {"amount": 320, "category": "餐饮", "note": "聚餐"}}
          ]
        }
        """
        let mutateTool = BaseAgentTool(operation: .recordMutate, runtime: runtime)
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
        let selectTool = BaseAgentTool(operation: .querySelect, runtime: runtime)
        result = try await selectTool.execute(arguments: try AgentToolArguments(json: selectArgs), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        #expect((envelope.data?["rows"] as? [[String: Any]])?.count == 2)

        // 7) 导出 CSV（外部文件通道）。
        let exportArgs = #"{"appID": "ledger", "table": "expenses"}"#
        let exportTool = BaseAgentTool(operation: .exportCSV, runtime: runtime)
        result = try await exportTool.execute(arguments: try AgentToolArguments(json: exportArgs), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        let csv = envelope.data?["csv"] as? String ?? ""
        #expect(csv.contains("amount,category,note"))
        #expect(csv.contains("320"))

        // 8) dryRun 导入不落库（走 mutate 校验路径）。
        let importArgs = """
        {"appID": "ledger", "table": "expenses", "dryRun": true,
          "rows": [{"amount": 88, "category": "购物", "note": "dry"}]}
        """
        let importTool = BaseAgentTool(operation: .importCSV, runtime: runtime)
        result = try await importTool.execute(arguments: try AgentToolArguments(json: importArgs), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        #expect(envelope.data?["dryRun"] as? Bool == true)
        #expect(envelope.data?["imported"] as? Int == 1)

        // 9) dryRun 后记录数不变。
        result = try await selectTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "table": "expenses"}"#), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect((envelope.data?["rows"] as? [[String: Any]])?.count == 3)

        await runtime.close()
    }

    // MARK: - 能力点门禁

    @Test func appCreateRejectsDeferredImportCapability() async throws {
        let runtime = try makeRuntime()
        let tool = BaseAgentTool(operation: .appCreate, runtime: runtime)
        await runtime.enterAuthoring(appID: "badapp")
        let args = """
        {
          "manifest": {
            "appID": "badapp", "name": "坏应用", "domain": "测试", "visibility": "private",
            "requiredCapabilities": ["import"]
          },
          "schema": {"tables": [{"name": "t", "fields": [{"name": "a", "type": "text"}]}]},
          \(Self.dualGuide)
        }
        """
        let result = try await tool.execute(arguments: try AgentToolArguments(json: args), context: baseToolContext())
        let envelope = try parseEnvelope(result)
        #expect(envelope.ok == false)
        #expect(envelope.errorCode == "CAPABILITY_REQUIRED")
        await runtime.close()
    }

    // MARK: - 契约

    /// legacy 行为保持：无 appID 的 base.guide 返回平台契约全文。
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
        await runtime.enterAuthoring(appID: "ledger")

        let createArgs = """
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [
            {"name": "expenses", "fields": [
              {"name": "amount", "type": "number", "required": true, "range": {"min": 0}},
              {"name": "category", "type": "enum", "options": ["餐饮", "交通", "购物"]},
              {"name": "note", "type": "text"}
            ]}
          ]},
          \(Self.dualGuide)
        }
        """
        let createTool = BaseAgentTool(operation: .appCreate, runtime: runtime)
        var result = try await createTool.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
        var envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)

        // “记一笔火锅 93” → mutate insert（含一笔交通、一笔咖啡）。
        let mutateTool = BaseAgentTool(operation: .recordMutate, runtime: runtime)
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
        let aggTool = BaseAgentTool(operation: .queryAggregate, runtime: runtime)
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
        await runtime.enterAuthoring(appID: "ledger")

        let createArgs = """
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [
            {"name": "expenses", "fields": [
              {"name": "amount", "type": "number", "required": true, "range": {"min": 0}},
              {"name": "category", "type": "enum", "options": ["餐饮", "交通"]},
              {"name": "note", "type": "text"}
            ]}
          ]},
          \(Self.dualGuide)
        }
        """
        let createTool = BaseAgentTool(operation: .appCreate, runtime: runtime)
        var result = try await createTool.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
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
        await runtime.enterAuthoring(appID: "ledger")
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = """
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [
            {"name": "expenses", "fields": [
              {"name": "amount", "type": "number", "required": true},
              {"name": "category", "type": "enum", "options": ["餐饮", "交通"]}
            ]}
          ]},
          \(Self.dualGuide)
        }
        """
        var result = try await create.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // 定义只读方法：本月餐饮汇总（aggregate + reply，数字必出内核）；同批同步双态指南。
        let defineTool = BaseAgentTool(operation: .methodDefine, runtime: runtime)
        let defineArgs = """
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
          \(Self.dualGuide)
        }
        """
        result = try await defineTool.execute(arguments: try AgentToolArguments(json: defineArgs), context: baseToolContext())
        let defEnvelope = try parseEnvelope(result)
        #expect(defEnvelope.ok == true)
        #expect(defEnvelope.data?["method"] as? String == "expenses.monthlyTotal")
        #expect(defEnvelope.data?["readOnly"] as? Bool == true)

        // 写 3 笔后调用方法：total 应出自内核（=485）。invoke 属运行面，无需制作面态。
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
        // M7：invoke 信封携带本次调用铸造的 traceId。
        let invokeTraceId = invokeEnvelope.data?["traceId"] as? String
        #expect(invokeTraceId?.isEmpty == false, "invoke 信封应携带 traceId")

        await runtime.close()
    }

    @Test func methodInvokeSurfacesWarnSignalAndRejectsIllegal() async throws {
        let runtime = try makeRuntime()
        await runtime.enterAuthoring(appID: "ledger")
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = """
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [
            {"name": "expenses", "fields": [
              {"name": "amount", "type": "number", "required": true},
              {"name": "category", "type": "enum", "options": ["餐饮", "交通"]}
            ]}
          ]},
          \(Self.dualGuide)
        }
        """
        var result = try await create.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // 定义带 assert warn 的方法：总额 > 100 发超预算信号（事实层不可压）。
        let defineTool = BaseAgentTool(operation: .methodDefine, runtime: runtime)
        let defineArgs = """
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
          \(Self.dualGuide)
        }
        """
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
        await runtime.enterAuthoring(appID: "ledger")
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = """
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          \(Self.dualGuide)
        }
        """
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

        // 移除唯一方法后 App 归零：M7 零方法兜底 → VALIDATION_FAILED + 制作面指引（非笼统 NOT_FOUND）。
        let invokeTool = BaseAgentTool(operation: .methodInvoke, runtime: runtime)
        result = try await invokeTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "method": "tmp", "input": {}}"#), context: baseToolContext())
        let envelope = try parseEnvelope(result)
        #expect(envelope.ok == false)
        #expect(envelope.errorCode == "VALIDATION_FAILED")
        #expect(envelope.errorHint == "该 App 尚未声明方法，请属主先在制作面完善")

        await runtime.close()
    }

    @Test func crossAppExportedMethodInvokeViaQualifiedName() async throws {
        let runtime = try makeRuntime()

        // 订阅 App（属主）提供一个 exported 只读方法。
        await runtime.enterAuthoring(appID: "subs")
        let subsCreate = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let subsArgs = """
        {
          "manifest": {"appID": "subs", "name": "订阅管理", "domain": "订阅", "visibility": "private"},
          "schema": {"tables": [{"name": "subs", "fields": [{"name": "amount", "type": "number"}]}]},
          \(Self.dualGuide)
        }
        """
        var result = try await subsCreate.execute(arguments: try AgentToolArguments(json: subsArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        let defineTool = BaseAgentTool(operation: .methodDefine, runtime: runtime)
        let defineArgs = """
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
          \(Self.dualGuide)
        }
        """
        result = try await defineTool.execute(arguments: try AgentToolArguments(json: defineArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // 订阅数据：两笔待扣。
        let subsMutate = BaseAgentTool(operation: .recordMutate, runtime: runtime)
        result = try await subsMutate.execute(arguments: try AgentToolArguments(json: #"{"appID": "subs", "table": "subs", "ops": [{"op": "insert", "record": {"amount": 68}}, {"op": "insert", "record": {"amount": 15}}]}"#), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // 记账 App：manifest imports 声明依赖 subs，再跨 App 调用全限定名（切换制作面目标）。
        await runtime.enterAuthoring(appID: "ledger")
        let ledgerCreate = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let ledgerArgs = """
        {
          "manifest": {
            "appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private",
            "requiredCapabilities": ["imports"],
            "imports": [{"appID": "subs", "methods": ["summary.monthly"]}]
          },
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          \(Self.dualGuide)
        }
        """
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
        await runtime.enterAuthoring(appID: "ledger")
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = """
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          \(Self.dualGuide)
        }
        """
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
        await runtime.enterAuthoring(appID: "ledger")
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = """
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          \(Self.dualGuide)
        }
        """
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
        await runtime.enterAuthoring(appID: "ledger")
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = """
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          \(Self.dualGuide)
        }
        """
        var result = try await create.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
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

        // 用 base.app.update 同批同步指南（双态）后，invoke 恢复可用。
        let updateTool = BaseAgentTool(operation: .appUpdate, runtime: runtime)
        result = try await updateTool.execute(arguments: try AgentToolArguments(json: """
        {
          "appID": "ledger", "basePackageVersion": 2,
          "guide": {
            "authoring": {"whenToUse": "属主建改时用", "whenNotToUse": "非属主不用", "sections": [], "methods": ["expenses.total"]},
            "usage": {"whenToUse": "记一笔或查月度总额时用", "whenNotToUse": "闲聊时不用", "sections": [], "methods": ["expenses.total"]}
          }
        }
        """), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        result = try await invokeTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "method": "expenses.total", "input": {}}"#), context: baseToolContext())
        let syncedEnvelope = try parseEnvelope(result)
        #expect(syncedEnvelope.ok == true)

        await runtime.close()
    }

    @Test func appUpdateWithSchemaWithoutGuideRejectsGuideOutOfSync() async throws {
        let runtime = try makeRuntime()
        await runtime.enterAuthoring(appID: "ledger")
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = """
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          \(Self.dualGuide)
        }
        """
        var result = try await create.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
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
        await runtime.enterAuthoring(appID: "ledger")
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = """
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          \(Self.dualGuide)
        }
        """
        var result = try await create.execute(arguments: try AgentToolArguments(json: createArgs), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)

        // 签名级变更：建第二张表（table.create），指南未同步 → 漂移。
        let tableTool = BaseAgentTool(operation: .tableCreate, runtime: runtime)
        result = try await tableTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "table": {"name": "categories", "fields": [{"name": "name", "type": "text"}]}}"#), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)
        #expect(try await runtime.isGuideOutOfSync(appID: "ledger") == true)

        // app.update 同批带 guide（双态）同步 → 漂移消除。
        let updateTool = BaseAgentTool(operation: .appUpdate, runtime: runtime)
        result = try await updateTool.execute(arguments: try AgentToolArguments(json: """
        {
          "appID": "ledger", "basePackageVersion": 2,
          "guide": {
            "authoring": {"whenToUse": "属主建改时用", "whenNotToUse": "非属主不用", "sections": [], "tables": ["expenses", "categories"]},
            "usage": {"whenToUse": "使用时参考", "whenNotToUse": "闲聊时不用", "sections": [], "tables": ["expenses", "categories"]}
          }
        }
        """), context: baseToolContext())
        #expect(try parseEnvelope(result).ok == true)
        #expect(try await runtime.isGuideOutOfSync(appID: "ledger") == false)

        // Card 暴露 guideOutOfSync 标志（app.get 同时结束制作面会话）。
        let getTool = BaseAgentTool(operation: .appGet, runtime: runtime)
        result = try await getTool.execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger"}"#), context: baseToolContext())
        let getEnvelope = try parseEnvelope(result)
        #expect(getEnvelope.ok == true)
        #expect(getEnvelope.data?["guideOutOfSync"] as? Bool == false)
        #expect(await runtime.isAuthoringMode(appID: "ledger") == false, "app.get 应退回使用面")

        await runtime.close()
    }

    // MARK: - M2-M4 只读报表方法纵切（记账月度报表）

    /// 报表 = 只读方法（v0.12 §2.4）：多聚合 + 趋势对比 + 预算超线 warn + reply 组合，数字必出内核。
    @Test func bookkeepingMonthlyReportReadOnlyVerticalSlice() async throws {
        let runtime = try makeRuntime()
        await runtime.enterAuthoring(appID: "ledger")

        // 1) 建正式私有记账 App（四件套同批，manifest 带一句话用途）。
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)
        let createArgs = """
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
          \(Self.dualGuide)
        }
        """
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

        // 3) 定义只读月度报表方法。
        let define = BaseAgentTool(operation: .methodDefine, runtime: runtime)
        let defineArgs = """
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
          \(Self.dualGuide)
        }
        """
        result = try await define.execute(arguments: try AgentToolArguments(json: defineArgs), context: baseToolContext())
        let defEnvelope = try parseEnvelope(result)
        #expect(defEnvelope.ok == true)
        #expect(defEnvelope.data?["readOnly"] as? Bool == true)

        // 4) 调用报表方法：数字必出内核，预算超线 warn 必现（事实层不可压）。
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

        // 5) 报表方法进入 App Card 方法摘要（app.get 同时退回使用面）。
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

    // MARK: - M7 制作面硬门禁（属主不豁免，与注册无关）

    /// 制作面工具在制作面会话之外 → PERMISSION_DENIED 信封（即使本机属主已建好该 App）。
    @Test func authoringToolsDeniedOutsideAuthoringSessionEvenForOwner() async throws {
        let runtime = try makeRuntime()
        var registry = AgentToolRegistry()
        registry.registerBaseTools(runtime: runtime)
        registry.registerBaseAuthoringTools(runtime: runtime)

        // 属主流程：进入制作面 → 建好 App → 退回使用面。
        await runtime.enterAuthoring(appID: "ledger")
        let created = try await call(registry, "base.app.create", Self.createArgs(appID: "ledger"))
        #expect(created["ok"] as? Bool == true)
        await runtime.exitAuthoring()

        // 属主已在本机持有该 App，但制作面会话已结束 → authoring 调用仍拒（属主不豁免）。
        let denied = try await call(registry, "base.record.mutate", #"{"appID": "ledger", "table": "expenses", "ops": [{"op": "insert", "record": {"amount": 1}}]}"#)
        #expect(denied["ok"] as? Bool == false)
        let error = denied["error"] as? [String: Any]
        #expect(error?["code"] as? String == "PERMISSION_DENIED")
        #expect((error?["hint"] as? String)?.contains("base.guide(appID, mode:") == true)
        #expect((error?["hint"] as? String)?.contains("base.method.invoke") == true)

        // 运行面工具不受影响：invoke 仍可用（此时 App 尚无方法 → VALIDATION_FAILED 而非权限错）。
        let invoke = try await call(registry, "base.method.invoke", #"{"appID": "ledger", "method": "anything", "input": {}}"#)
        #expect(invoke["ok"] as? Bool == false)
        #expect((invoke["error"] as? [String: Any])?["code"] as? String == "VALIDATION_FAILED")
        #expect(((invoke["error"] as? [String: Any])?["hint"] as? String)?.contains("尚未声明方法") == true)

        await runtime.close()
    }

    /// guide(appID, mode:"authoring") 解锁制作面；guide usage / app.get 退回使用面重新上锁。
    @Test func guideAuthoringUnlocksAndUsageAppGetRelocks() async throws {
        let runtime = try makeRuntime()
        var registry = AgentToolRegistry()
        registry.registerBaseTools(runtime: runtime)
        registry.registerBaseAuthoringTools(runtime: runtime)

        // 属主建 App。
        await runtime.enterAuthoring(appID: "ledger")
        _ = try await call(registry, "base.app.create", Self.createArgs(appID: "ledger"))

        // 非属主：本机不存在该 App 的子库 → PERMISSION_DENIED「仅属主可在本机制作」。
        let ghost = try await call(registry, "base.guide", #"{"appID": "ghost", "mode": "authoring"}"#)
        #expect(ghost["ok"] as? Bool == false)
        #expect((ghost["error"] as? [String: Any])?["code"] as? String == "PERMISSION_DENIED")

        // 解锁：guide(authoring) → mode=authoring + guide.authoring + 制作面前言。
        await runtime.exitAuthoring()
        let authoring = try await call(registry, "base.guide", #"{"appID": "ledger", "mode": "authoring"}"#)
        #expect(authoring["ok"] as? Bool == true)
        let authoringData = authoring["data"] as? [String: Any]
        #expect(authoringData?["mode"] as? String == "authoring")
        #expect((authoringData?["guide"] as? [String: Any])?["whenToUse"] != nil)
        #expect(((authoringData?["preamble"] as? String) ?? "").contains("authoring"))
        #expect(await runtime.isAuthoringMode(appID: "ledger") == true)

        // 解锁后 authoring 工具可执行（同 appID）。
        let mutate = try await call(registry, "base.record.mutate", #"{"appID": "ledger", "table": "expenses", "ops": [{"op": "insert", "record": {"amount": 10}}]}"#)
        #expect(mutate["ok"] as? Bool == true)

        // 切换目标 App：为另一 appID 的 authoring 调用仍拒。
        await runtime.enterAuthoring(appID: "other")
        let wrongApp = try await call(registry, "base.record.mutate", #"{"appID": "ledger", "table": "expenses", "ops": [{"op": "insert", "record": {"amount": 1}}]}"#)
        #expect(wrongApp["ok"] as? Bool == false)

        // 重新解锁 ledger 后，guide(appID)（usage 缺省态）退回使用面。
        await runtime.enterAuthoring(appID: "ledger")
        let usage = try await call(registry, "base.guide", #"{"appID": "ledger"}"#)
        #expect(usage["ok"] as? Bool == true)
        #expect((usage["data"] as? [String: Any])?["mode"] as? String == "usage")
        #expect(await runtime.isAuthoringMode(appID: "ledger") == false)
        let deniedAgain = try await call(registry, "base.record.mutate", #"{"appID": "ledger", "table": "expenses", "ops": [{"op": "insert", "record": {"amount": 2}}]}"#)
        #expect(deniedAgain["ok"] as? Bool == false)

        // app.get 也退回使用面。
        await runtime.enterAuthoring(appID: "ledger")
        let card = try await call(registry, "base.app.get", #"{"appID": "ledger"}"#)
        #expect(card["ok"] as? Bool == true)
        #expect(await runtime.isAuthoringMode(appID: "ledger") == false)

        await runtime.close()
    }

    // MARK: - M7 guide 双态硬切

    /// guide 必须为 {authoring, usage} 双态：单态/旧版平面 guide 在 create/update 一律 VALIDATION_FAILED。
    @Test func guideMustBeDualStateOnCreateAndUpdate() async throws {
        let runtime = try makeRuntime()
        await runtime.enterAuthoring(appID: "ledger")
        let create = BaseAgentTool(operation: .appCreate, runtime: runtime)

        // 只带 authoring 态 → 缺 usage。
        let authoringOnly = """
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          "guide": {"authoring": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}}
        }
        """
        var result = try await create.execute(arguments: try AgentToolArguments(json: authoringOnly), context: baseToolContext())
        var envelope = try parseEnvelope(result)
        #expect(envelope.ok == false)
        #expect(envelope.errorCode == "VALIDATION_FAILED")
        #expect(envelope.errorHint?.contains("authoring + usage") == true)

        // 只带 usage 态 → 缺 authoring。
        let usageOnly = """
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          "guide": {"usage": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}}
        }
        """
        result = try await create.execute(arguments: try AgentToolArguments(json: usageOnly), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == false)
        #expect(envelope.errorCode == "VALIDATION_FAILED")
        #expect(envelope.errorHint?.contains("authoring + usage") == true)

        // 旧版平面 guide（无双态键）→ 同拒。
        let legacyFlat = """
        {
          "manifest": {"appID": "ledger", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}]}]},
          "guide": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}
        }
        """
        result = try await create.execute(arguments: try AgentToolArguments(json: legacyFlat), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == false)
        #expect(envelope.errorCode == "VALIDATION_FAILED")

        // 双态齐全 → 创建成功；Card 携带 methodsEmpty + 零方法 hint。
        result = try await create.execute(arguments: try AgentToolArguments(json: Self.createArgs(appID: "ledger")), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == true)
        #expect(envelope.data?["methodsEmpty"] as? Bool == true)
        #expect(envelope.data?["hint"] as? String == "该 App 尚未声明方法，请属主先在制作面完善")

        // update 提供单态 guide → VALIDATION_FAILED。
        let updateTool = BaseAgentTool(operation: .appUpdate, runtime: runtime)
        result = try await updateTool.execute(arguments: try AgentToolArguments(json: """
        {"appID": "ledger", "basePackageVersion": 1,
         "guide": {"usage": {"whenToUse": "x", "whenNotToUse": "y", "sections": []}}}
        """), context: baseToolContext())
        envelope = try parseEnvelope(result)
        #expect(envelope.ok == false)
        #expect(envelope.errorCode == "VALIDATION_FAILED")

        await runtime.close()
    }

    // MARK: - M7 零方法 App 运行面兜底

    @Test func invokeOnZeroMethodAppFailsWithAuthoringHint() async throws {
        let runtime = try makeRuntime()
        await runtime.enterAuthoring(appID: "ledger")
        _ = try await BaseAgentTool(operation: .appCreate, runtime: runtime)
            .execute(arguments: try AgentToolArguments(json: Self.createArgs(appID: "ledger")), context: baseToolContext())

        // 退出制作面（运行面视角）后 invoke → VALIDATION_FAILED + 制作面指引。
        await runtime.exitAuthoring()
        let result = try await BaseAgentTool(operation: .methodInvoke, runtime: runtime)
            .execute(arguments: try AgentToolArguments(json: #"{"appID": "ledger", "method": "any", "input": {}}"#), context: baseToolContext())
        let envelope = try parseEnvelope(result)
        #expect(envelope.ok == false)
        #expect(envelope.errorCode == "VALIDATION_FAILED")
        #expect(envelope.errorHint == "该 App 尚未声明方法，请属主先在制作面完善")

        await runtime.close()
    }

    // MARK: - M7 export.csv 方法步骤（工具层端到端）

    @Test func exportCSVMethodStepEndToEnd() async throws {
        let runtime = try makeRuntime()
        await runtime.enterAuthoring(appID: "ledger")
        var registry = AgentToolRegistry()
        registry.registerBaseTools(runtime: runtime)
        registry.registerBaseAuthoringTools(runtime: runtime)

        _ = try await call(registry, "base.app.create", Self.createArgs(appID: "ledger"))
        _ = try await call(registry, "base.record.mutate", #"""
        {"appID": "ledger", "table": "expenses", "ops": [
          {"op": "insert", "record": {"amount": 93, "note": "火锅"}},
          {"op": "insert", "record": {"amount": 45, "note": "地铁"}}
        ]}
        """#)

        // 定义含 export.csv 步骤的方法（列白名单 + maxRows；非只读）。
        _ = try await call(registry, "base.method.define", """
        {"appID": "ledger",
         "method": {
           "name": "expenses.export",
           "description": "导出支出流水 CSV",
           "steps": [
             {"type": "export.csv", "table": "expenses", "columns": ["note", "amount"], "maxRows": 100, "as": "csv"},
             {"type": "reply", "template": {"csv": "$csv.csv", "rows": "$csv.rowCount"}}
           ]
         },
         \(Self.dualGuide)}
        """)

        let invoke = try await call(registry, "base.method.invoke", #"{"appID": "ledger", "method": "expenses.export", "input": {}}"#)
        #expect(invoke["ok"] as? Bool == true)
        let data = invoke["data"] as? [String: Any]
        let inner = data?["data"] as? [String: Any]
        let csv = inner?["csv"] as? String ?? ""
        #expect(csv.hasPrefix("note,amount\r\n"), "表头应为声明列顺序")
        #expect(csv.contains("火锅"))
        #expect((inner?["rows"] as? NSNumber)?.intValue == 2)

        // 负例 1：声明列含 schema 未知列 → VALIDATION_FAILED。
        _ = try await call(registry, "base.method.define", """
        {"appID": "ledger",
         "method": {
           "name": "expenses.export.bad",
           "steps": [{"type": "export.csv", "table": "expenses", "columns": ["amount", "nonsense"]}]
         },
         \(Self.dualGuide)}
        """)
        let badColumn = try await call(registry, "base.method.invoke", #"{"appID": "ledger", "method": "expenses.export.bad", "input": {}}"#)
        #expect(badColumn["ok"] as? Bool == false)
        #expect((badColumn["error"] as? [String: Any])?["code"] as? String == "VALIDATION_FAILED")

        // 负例 2：行数超 maxRows → VALIDATION_FAILED。
        _ = try await call(registry, "base.method.define", """
        {"appID": "ledger",
         "method": {
           "name": "expenses.export.capped",
           "steps": [{"type": "export.csv", "table": "expenses", "columns": ["amount"], "maxRows": 1}]
         },
         \(Self.dualGuide)}
        """)
        let capped = try await call(registry, "base.method.invoke", #"{"appID": "ledger", "method": "expenses.export.capped", "input": {}}"#)
        #expect(capped["ok"] as? Bool == false)
        #expect(((capped["error"] as? [String: Any])?["message"] as? String)?.contains("maxRows=1") == true)

        await runtime.close()
    }

    // MARK: - M7 步骤审计 traceId 贯穿

    /// 一次 invoke 的全部 method.step 审计行共享信封返回的同一个 traceId。
    @Test func methodStepAuditRowsShareInvokeTraceId() async throws {
        let runtime = try makeRuntime()
        await runtime.enterAuthoring(appID: "ledger")
        var registry = AgentToolRegistry()
        registry.registerBaseTools(runtime: runtime)
        registry.registerBaseAuthoringTools(runtime: runtime)

        _ = try await call(registry, "base.app.create", Self.createArgs(appID: "ledger"))
        _ = try await call(registry, "base.record.mutate", #"{"appID": "ledger", "table": "expenses", "ops": [{"op": "insert", "record": {"amount": 93}}]}"#)
        _ = try await call(registry, "base.method.define", """
        {"appID": "ledger",
         "method": {
           "name": "expenses.report",
           "steps": [
             {"type": "aggregate", "table": "expenses", "aggregations": [{"op": "sum", "field": "amount", "alias": "total"}], "as": "agg"},
             {"type": "assert", "on": {"path": "$agg.0.total", "op": "lte", "value": 100}, "onFail": "warn", "message": "超 100"},
             {"type": "reply", "template": {"total": "$agg.0.total"}}
           ]
         },
         \(Self.dualGuide)}
        """)

        let invoke = try await call(registry, "base.method.invoke", #"{"appID": "ledger", "method": "expenses.report", "input": {}}"#)
        #expect(invoke["ok"] as? Bool == true)
        let traceId = try #require((invoke["data"] as? [String: Any])?["traceId"] as? String)
        #expect(!traceId.isEmpty)

        // 等 execute 末尾 defer 的审计 Task 落地。
        try await Task.sleep(for: .milliseconds(300))

        let audit = await runtime.readAudit(appID: "ledger")
        let stepRows = audit.filter { $0["operation"] == "method.step" }
        #expect(stepRows.count >= 3, "aggregate/assert/reply 三步应各有一条 method.step 审计")
        for row in stepRows {
            let detailJSON = try #require(row["detail"])
            let detail = try #require(try JSONSerialization.jsonObject(with: Data(detailJSON.utf8)) as? [String: Any])
            #expect(detail["traceId"] as? String == traceId, "步骤审计应共享 invoke 的 traceId")
            #expect(detail["methodName"] as? String == "expenses.report")
            #expect(detail["surface"] as? String == "runtime")
        }
        let stepTypes = Set(stepRows.compactMap { row -> String? in
            guard let detailJSON = row["detail"],
                  let detail = try? JSONSerialization.jsonObject(with: Data(detailJSON.utf8)) as? [String: Any] else { return nil }
            return detail["stepType"] as? String
        })
        #expect(stepTypes == ["aggregate", "assert", "reply"])

        await runtime.close()
    }

    // MARK: - M7 免审批（base.* 永不弹人工确认）

    /// 所有 base.* 工具调用免用户审批：readOnly 模式（最严档）下 base 读写/制作面操作全部
    /// 静默放行——权限面不再是边界，唯一边界是工具面（authoring 硬门禁）。
    @Test func baseToolsNeverPromptForApprovalEvenInReadOnlyMode() async throws {
        let runtime = try makeRuntime()
        var registry = AgentToolRegistry()
        registry.registerBaseTools(runtime: runtime)
        registry.registerBaseAuthoringTools(runtime: runtime)

        let readOnlyContext = AgentToolExecutionContext(
            runID: "run-ro",
            sessionID: "session",
            groupID: "group",
            userPrompt: "base approval test",
            toolCallID: UUID().uuidString,
            policyEngine: AgentPolicyEngine(permissionMode: .readOnly)
        )

        // 运行面只读工具：直接执行，无审批。
        let list = try await call(registry, "base.app.list", "{}", context: readOnlyContext)
        #expect(list["ok"] as? Bool == true)
        let contract = try await call(registry, "base.guide", "{}", context: readOnlyContext)
        #expect(contract["ok"] as? Bool == true)

        // 制作面写工具（建 App）在 readOnly 模式下同样免审批执行。
        await runtime.enterAuthoring(appID: "ledger")
        let created = try await call(registry, "base.app.create", Self.createArgs(appID: "ledger"), context: readOnlyContext)
        #expect(created["ok"] as? Bool == true, "readOnly 模式下 base 写操作应免审批放行")

        // 制作面写工具（mutate）亦免审批。
        let mutated = try await call(registry, "base.record.mutate", #"{"appID": "ledger", "table": "expenses", "ops": [{"op": "insert", "record": {"amount": 7}}]}"#, context: readOnlyContext)
        #expect(mutated["ok"] as? Bool == true)

        // 运行面执行工具（method.invoke）免审批。
        _ = try await call(registry, "base.method.define", """
        {"appID": "ledger",
         "method": {"name": "expenses.total", "readOnly": true, "steps": [
           {"type": "aggregate", "table": "expenses", "aggregations": [{"op": "sum", "field": "amount", "alias": "total"}], "as": "agg"},
           {"type": "reply", "template": {"total": "$agg.0.total"}}
         ]},
         \(Self.dualGuide)}
        """, context: readOnlyContext)
        let invoked = try await call(registry, "base.method.invoke", #"{"appID": "ledger", "method": "expenses.total", "input": {}}"#, context: readOnlyContext)
        #expect(invoked["ok"] as? Bool == true)
        #expect(((invoked["data"] as? [String: Any])?["data"] as? [String: Any])?["total"] as? Double == 7)

        await runtime.close()
    }

    // MARK: - Helpers

    /// M7 双态指南标准夹具（authoring + usage）。
    private static let dualGuide = """
        "guide": {
          "authoring": {"whenToUse": "属主建改 App 时用", "whenNotToUse": "非属主不用", "sections": []},
          "usage": {"whenToUse": "当用户说记一笔且是个人收支时用", "whenNotToUse": "当只是闲聊消费观时不用", "sections": []}
        }
    """

    /// 标准建 App 参数（双态指南）。
    private static func createArgs(appID: String) -> String {
        """
        {
          "manifest": {"appID": "\(appID)", "name": "记账本", "domain": "记账", "visibility": "private"},
          "schema": {"tables": [{"name": "expenses", "fields": [{"name": "amount", "type": "number"}, {"name": "note", "type": "text"}]}]},
          \(dualGuide)
        }
        """
    }

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

    /// 经 AgentToolRegistry.execute 走完整链路（含策略引擎审批判定）。
    private func call(
        _ registry: AgentToolRegistry,
        _ name: String,
        _ json: String,
        context: AgentToolExecutionContext? = nil
    ) async throws -> [String: Any] {
        let toolContext = context ?? baseToolContext()
        let result = try await registry.execute(
            AgentToolCall(name: name, argumentsJSON: json),
            context: toolContext
        )
        let json_ = try #require(result.contentJSON)
        return try #require(try JSONSerialization.jsonObject(with: Data(json_.utf8)) as? [String: Any])
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
