import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Suite("AgentToolBatchPagination 统一分批/分页契约")
struct AgentToolBatchPaginationTests {
    @Test("validatedPageSize 规范化缺省值与上限")
    func validatedPageSizeNormalizesAndEnforcesLimits() async throws {
        #expect(try AgentToolBatchPagination.validatedPageSize(nil) == 50)
        #expect(try AgentToolBatchPagination.validatedPageSize(100) == 100)
        #expect(try AgentToolBatchPagination.validatedPageSize(1) == 1)
        #expect(try AgentToolBatchPagination.validatedPageSize(nil, default: 25, max: 200) == 25)
        await #expect(throws: AgentToolError.self) {
            _ = try AgentToolBatchPagination.validatedPageSize(101)
        }
        await #expect(throws: AgentToolError.self) {
            _ = try AgentToolBatchPagination.validatedPageSize(0)
        }
    }

    @Test("validate 拒绝小于 1 的页码")
    func validateRejectsNonPositivePage() async throws {
        try AgentToolBatchPagination.validate(page: 1)
        await #expect(throws: AgentToolError.self) {
            try AgentToolBatchPagination.validate(page: 0)
        }
    }

    @Test("paginationContract 覆盖工具名与 nextPage 契约")
    func paginationContractMentionsToolAndNextPage() {
        let contract = AgentToolBatchPagination.paginationContract(listToolName: "session_list_by_status")
        #expect(contract.contains("session_list_by_status"))
        #expect(contract.contains("`nextPage`"))
        #expect(contract.contains("default 50"))
        #expect(contract.contains("max 100"))
        #expect(contract.contains("repeat until `nextPage` is null"))
    }

    @Test("batchContract 覆盖工具名与每批上限")
    func batchContractMentionsToolAndCap() {
        let contract = AgentToolBatchPagination.batchContract(toolName: "session_batch_delete", maxItemsPerCall: 50)
        #expect(contract.contains("session_batch_delete"))
        #expect(contract.contains("at most 50 items"))
        #expect(contract.contains("call session_batch_delete again"))
    }

    @Test("promptRule 是「读一批处理一批」的唯一来源")
    func promptRuleCoversBatchReadAndWritePatterns() {
        let rule = AgentToolBatchPagination.promptRule
        #expect(rule.contains("immediately follow every exact non-null `nextPage`"))
        #expect(rule.contains("repeat until `nextPage` is null"))
        #expect(rule.contains("at most \(AgentToolBatchPagination.defaultBatchSize) items per call"))
        #expect(rule.contains("split the work into batches"))
    }
}
