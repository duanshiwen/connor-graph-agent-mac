import Foundation
import Testing
import ConnorGraphAgent

@Suite("Agent Model Message Protocol Repair")
struct AgentModelMessageProtocolRepairTests {

    @Test func validToolSequenceIsUnchanged() {
        let messages = [
            systemMessage(),
            userMessage("question"),
            assistantMessage(toolCalls: [("a", "read"), ("b", "read")]),
            toolMessage(id: "a"),
            toolMessage(id: "b"),
            userMessage("next")
        ]
        #expect(AgentModelMessageProtocolRepair.repairing(messages) == messages)
    }

    @Test func interleavedRealToolResultIsPromotedBackIntoContiguousRun() {
        let messages = [
            assistantMessage(toolCalls: [("a", "read"), ("b", "read")]),
            toolMessage(id: "a"),
            userMessage("attachment context"),
            toolMessage(id: "b")
        ]
        let repaired = AgentModelMessageProtocolRepair.repairing(messages)
        assertProtocolValid(repaired)
        #expect(repaired.map(\.role) == [.assistant, .tool, .tool, .user])
        #expect(repaired[1].toolCallID == "a")
        #expect(repaired[2].toolCallID == "b")
        #expect(repaired[3].role == .user)
        #expect(repaired[3].content.contains("attachment context"))
    }

    @Test func missingToolResultGetsPlaceholderInsteadOfDanglingCall() {
        let messages = [
            assistantMessage(toolCalls: [("a", "read"), ("b", "read")]),
            toolMessage(id: "a"),
            userMessage("next")
        ]
        let repaired = AgentModelMessageProtocolRepair.repairing(messages)
        assertProtocolValid(repaired)
        #expect(repaired.count == 4)
        let placeholder = repaired[2]
        #expect(placeholder.role == .tool)
        #expect(placeholder.toolCallID == "b")
        #expect(placeholder.content.hasPrefix(AgentModelMessageProtocolRepair.interruptedToolResultPrefix))
    }

    @Test func assistantToolCallsWithNoResultsGetPlaceholdersForEveryCall() {
        let messages = [
            assistantMessage(toolCalls: [("a", "read"), ("b", "read")]),
            userMessage("next")
        ]
        let repaired = AgentModelMessageProtocolRepair.repairing(messages)
        assertProtocolValid(repaired)
        #expect(repaired.map(\.role) == [.assistant, .tool, .tool, .user])
        #expect(repaired[1].toolCallID == "a")
        #expect(repaired[1].content.hasPrefix(AgentModelMessageProtocolRepair.interruptedToolResultPrefix))
        #expect(repaired[2].toolCallID == "b")
        #expect(repaired[2].content.hasPrefix(AgentModelMessageProtocolRepair.interruptedToolResultPrefix))
    }

    @Test func repairDoesNotCrossIntoTheNextAssistantToolCallsTurn() {
        let messages = [
            assistantMessage(toolCalls: [("a", "read"), ("b", "read")]),
            toolMessage(id: "a"),
            userMessage("next"),
            assistantMessage(toolCalls: [("c", "read")]),
            toolMessage(id: "c")
        ]
        let repaired = AgentModelMessageProtocolRepair.repairing(messages)
        assertProtocolValid(repaired)
        #expect(repaired.map(\.role) == [.assistant, .tool, .tool, .user, .assistant, .tool])
        #expect(repaired[2].toolCallID == "b")
        #expect(repaired[2].content.hasPrefix(AgentModelMessageProtocolRepair.interruptedToolResultPrefix))
        #expect(repaired[5].toolCallID == "c")
        #expect(repaired[5].content.contains("result c"))
    }

    @Test func repairIsIdempotent() {
        let messages = [
            assistantMessage(toolCalls: [("a", "read"), ("b", "read")]),
            toolMessage(id: "a"),
            userMessage("attachment context"),
            toolMessage(id: "b"),
            assistantMessage(toolCalls: [("c", "read")])
        ]
        let once = AgentModelMessageProtocolRepair.repairing(messages)
        let twice = AgentModelMessageProtocolRepair.repairing(once)
        #expect(twice == once)
        assertProtocolValid(twice)
    }

    // MARK: - Helpers

    private func systemMessage(_ text: String = "system prompt") -> AgentModelMessage {
        AgentModelMessage(role: .system, content: text)
    }

    private func userMessage(_ text: String) -> AgentModelMessage {
        AgentModelMessage(role: .user, content: text)
    }

    private func assistantMessage(toolCalls: [(id: String, name: String)]) -> AgentModelMessage {
        AgentModelMessage(
            role: .assistant,
            content: "",
            toolCalls: toolCalls.map { AgentToolCall(id: $0.id, name: $0.name, argumentsJSON: "{}") }
        )
    }

    private func toolMessage(id: String) -> AgentModelMessage {
        AgentModelMessage(role: .tool, content: "result \(id)", toolCallID: id, name: "read")
    }

    private func assertProtocolValid(_ messages: [AgentModelMessage]) {
        for (index, message) in messages.enumerated() {
            guard message.role == .assistant,
                  let calls = message.toolCalls,
                  !calls.isEmpty else { continue }
            var missing = Set(calls.map(\.id))
            for next in messages.dropFirst(index + 1) {
                if let id = next.toolCallID, missing.contains(id) {
                    missing.remove(id)
                    if missing.isEmpty { break }
                    continue
                }
                if !missing.isEmpty {
                    Issue.record("Non-tool message appeared before all tool results; missing \(missing.sorted())")
                    return
                }
            }
            if !missing.isEmpty {
                Issue.record("Tool results missing for \(missing.sorted())")
            }
        }
    }
}
