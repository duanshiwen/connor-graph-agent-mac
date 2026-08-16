import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

@Suite("PDF generation agent tool")
struct PDFAgentToolTests {
    private func makeTool() throws -> (GeneratePDFAgentTool, AppStoragePaths) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-tool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        return (GeneratePDFAgentTool(store: AppSessionAttachmentStore(paths: paths)), paths)
    }

    private func context() -> AgentToolExecutionContext {
        AgentToolExecutionContext(
            runID: "run", sessionID: "session", groupID: "group", userPrompt: "生成PDF",
            toolCallID: "call", policyEngine: AgentPolicyEngine(permissionMode: .allowAll),
            approvedCapabilities: [.mutateSessionStatus]
        )
    }

    @Test func generatesAndAttachesPDF() async throws {
        let (tool, paths) = try makeTool()
        defer { try? FileManager.default.removeItem(at: paths.applicationSupportDirectory) }
        let arguments = try AgentToolArguments(json: ##"{"title":"测试报告","content":"# 标题\n\n- 第一点\n- 第二点"}"##)

        let result = try await tool.execute(arguments: arguments, context: context())

        #expect(result.toolName == "generate_pdf")
        #expect(result.contentText.contains("PDF 已生成"))
        #expect(result.contentText.contains(".pdf"))
        let json = try #require(result.contentJSON)
        let payload = try JSONDecoder().decode(PDFAgentToolResultPayload.self, from: Data(json.utf8))
        #expect(payload.pageCount == 1)
        #expect(payload.byteCount > 0)
        #expect(payload.fileName.hasSuffix(".pdf"))
        #expect(FileManager.default.fileExists(atPath: payload.localFileURL.path))
    }

    @Test func rejectsEmptyContent() async throws {
        let (tool, paths) = try makeTool()
        defer { try? FileManager.default.removeItem(at: paths.applicationSupportDirectory) }
        let arguments = try AgentToolArguments(json: ##"{"content":"   "}"##)

        await #expect(throws: GeneratePDFAgentToolError.emptyContent) {
            _ = try await tool.execute(arguments: arguments, context: context())
        }
    }
}
