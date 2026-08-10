import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
@testable import ConnorGraphAppSupport
import ConnorGraphStore

@Suite("Preflight Tool Argument Normalization")
struct PreflightToolArgumentNormalizationTests {
    @Test func memoryContextToolsAcceptStringIntegerArguments() async throws {
        // 模型常把 page/pageSize/depth 发成字符串，工具应转成整数而不是拒绝。
        let normalized = MemoryOSLayeredContextSupport.normalizeLegacyArguments(
            try AgentToolArguments(json: #"{"query":"官网","page":"2","pageSize":"100"}"#),
            includeDepth: false
        )
        #expect(normalized.int("page") == 2)
        #expect(normalized.int("pageSize") == 100)

        let normalizedKnowledge = MemoryOSLayeredContextSupport.normalizeLegacyArguments(
            try AgentToolArguments(json: #"{"query":"官网","page":"3","pageSize":"50","depth":"2"}"#),
            includeDepth: true
        )
        #expect(normalizedKnowledge.int("page") == 3)
        #expect(normalizedKnowledge.int("pageSize") == 50)
        #expect(normalizedKnowledge.int("depth") == 2)
    }

    @Test func noteSearchToolAcceptsStringPageAndRunsWithoutThrowing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("note-arg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteGraphKernelStore(path: root.appendingPathComponent("connor.sqlite").path)
        try store.migrate()
        let tool = NoteSearchTool(search: NoteSearchService(repository: AppNoteRepository(store: store)))

        let normalized = tool.normalizeLegacyArguments(try AgentToolArguments(json: #"{"query":"官网","page":"1"}"#))
        #expect(normalized.int("page") == 1)

        // 用字符串 page 执行不应抛错（返回结构化成功/空结果）。
        let context = AgentToolExecutionContext(
            runID: "run", sessionID: "session", groupID: "default", userPrompt: "search notes",
            toolCallID: "call", policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
        let result = try await tool.execute(
            arguments: normalized,
            context: context
        )
        #expect(result.error == nil)
    }

    @Test func memoryRecentContextToolAcceptsStringPageSizeWithoutThrowing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mem-arg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteMemoryOSStore(path: root.appendingPathComponent("memory-os.sqlite").path)
        try store.migrate()
        let tool = MemoryOSRecentContextTool(facade: AppMemoryOSFacade(store: store))

        let normalized = tool.normalizeLegacyArguments(try AgentToolArguments(json: #"{"query":"官网","page":"1","pageSize":"100"}"#))
        #expect(normalized.int("page") == 1)
        #expect(normalized.int("pageSize") == 100)

        let context = AgentToolExecutionContext(
            runID: "run", sessionID: "session", groupID: "default", userPrompt: "search memory",
            toolCallID: "call", policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
        let result = try await tool.execute(arguments: normalized, context: context)
        #expect(result.error == nil)
    }
}
