import Foundation
import Testing
@testable import ConnorGraphAgent

@Suite("Browser Assisted Web Tool Tests")
struct BrowserAssistedWebToolTests {
    @Test func googleWebSearchUsesBrowserAssistedHandler() async throws {
        final class Recorder: @unchecked Sendable {
            var requests: [BrowserAssistedSearchRequest] = []
        }
        let recorder = Recorder()
        let tool = SearchEngineMCPTool(browserAssistedSearchHandler: { request in
            recorder.requests.append(request)
            return BrowserAssistedSearchResult(
                taskID: "task-1",
                sessionID: "session-1",
                tabID: "tab-1",
                urlString: request.urlString,
                status: "running"
            )
        })

        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "query": .string("Connor Graph Agent"),
                "engine": .string("google"),
                "max_results": .int(3)
            ]),
            context: Self.context()
        )

        #expect(recorder.requests.count == 1)
        #expect(recorder.requests.first?.engine == "google")
        #expect(recorder.requests.first?.revealImmediately == false)
        #expect(recorder.requests.first?.urlString.contains("www.google.com/search") == true)
        #expect(result.contentText.contains("built-in browser background runner"))
        #expect(result.contentText.contains("Task ID: task-1"))
    }

    @Test func javascriptWebFetchUsesBrowserAssistedHandler() async throws {
        final class Recorder: @unchecked Sendable {
            var requests: [BrowserAssistedSearchRequest] = []
        }
        let recorder = Recorder()
        let tool = SearchEngineMCPWebFetchTool(browserAssistedSearchHandler: { request in
            recorder.requests.append(request)
            return BrowserAssistedSearchResult(
                taskID: "task-2",
                sessionID: "session-2",
                tabID: "tab-2",
                urlString: request.urlString,
                status: "running"
            )
        })

        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "url": .string("https://example.com/app"),
                "render_mode": .string("js")
            ]),
            context: Self.context()
        )

        #expect(recorder.requests.count == 1)
        #expect(recorder.requests.first?.engine == "direct-url")
        #expect(recorder.requests.first?.urlString == "https://example.com/app")
        #expect(result.contentText.contains("built-in browser background runner"))
        #expect(result.contentText.contains("Task ID: task-2"))
    }

    private static func context() -> AgentToolExecutionContext {
        let audit = InMemoryAgentAuditLog()
        let policy = AgentPolicyEngine(permissionMode: .allowAll, auditLog: audit)
        return AgentToolExecutionContext(
            runID: "run-1",
            sessionID: "session-1",
            groupID: "default",
            userPrompt: "search",
            toolCallID: "tool-call-1",
            policyEngine: policy
        )
    }
}
