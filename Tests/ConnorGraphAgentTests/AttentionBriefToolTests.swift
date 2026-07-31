import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAgent

@Suite struct AttentionBriefToolTests {
    @Test func attentionBriefCombinesAllCalendarsAndRecentReceivedMailInOneCall() async throws {
        let now = Date()
        let calendarRuntime = InMemoryAgentCalendarRuntime(events: [
            CalendarEvent(
                id: CalendarEventID(rawValue: "event-a"),
                calendarID: CalendarID(rawValue: "calendar-a"),
                title: "Doctor visit",
                start: CalendarEventDateTime(date: now.addingTimeInterval(3_600)),
                end: CalendarEventDateTime(date: now.addingTimeInterval(7_200))
            ),
            CalendarEvent(
                id: CalendarEventID(rawValue: "event-b"),
                calendarID: CalendarID(rawValue: "calendar-b"),
                title: "Flight",
                start: CalendarEventDateTime(date: now.addingTimeInterval(86_400)),
                end: CalendarEventDateTime(date: now.addingTimeInterval(90_000))
            ),
            CalendarEvent(
                id: CalendarEventID(rawValue: "event-far"),
                calendarID: CalendarID(rawValue: "calendar-a"),
                title: "Far event",
                start: CalendarEventDateTime(date: now.addingTimeInterval(10 * 86_400)),
                end: CalendarEventDateTime(date: now.addingTimeInterval(10 * 86_400 + 3_600))
            )
        ])
        let mailRuntime = StubMailRuntime(messages: [Self.message(id: "mail-1", subject: "Invoice due")])
        let tool = AttentionBriefTool(calendarRuntime: calendarRuntime, mailRuntime: mailRuntime)

        let result = try await tool.execute(arguments: AgentToolArguments(values: [:]), context: Self.context(toolCallID: "brief-1"))

        let object = try #require(try Self.jsonObject(result) as? [String: Any])
        let events = try #require(object["events"] as? [[String: Any]])
        #expect(events.map { $0["eventID"] as? String } == ["event-a", "event-b"])
        let mail = try #require(object["mail"] as? [String: Any])
        #expect(mail["status"] as? String == "included")
        let messages = try #require(mail["messages"] as? [[String: Any]])
        #expect(messages.first?["messageID"] as? String == "mail-1")
        let recentRequest = await mailRuntime.lastRecentRequest
        #expect(recentRequest?.accountID == nil)
        #expect(recentRequest?.direction == .received)
        #expect(result.contentText.contains("all calendars"))
        #expect(result.contentText.contains("Invoice due"))
    }

    @Test func attentionBriefDegradesToCalendarOnlyWithoutMailRuntime() async throws {
        let now = Date()
        let calendarRuntime = InMemoryAgentCalendarRuntime(events: [
            CalendarEvent(
                id: CalendarEventID(rawValue: "event-solo"),
                calendarID: CalendarID(rawValue: "calendar-a"),
                title: "Standup",
                start: CalendarEventDateTime(date: now.addingTimeInterval(1_800)),
                end: CalendarEventDateTime(date: now.addingTimeInterval(3_600))
            )
        ])
        let tool = AttentionBriefTool(calendarRuntime: calendarRuntime)

        let result = try await tool.execute(arguments: AgentToolArguments(values: [:]), context: Self.context(toolCallID: "brief-2"))

        let object = try #require(try Self.jsonObject(result) as? [String: Any])
        let events = try #require(object["events"] as? [[String: Any]])
        #expect(events.count == 1)
        let mail = try #require(object["mail"] as? [String: Any])
        #expect(mail["status"] as? String == "unavailable")
    }

    @Test func attentionBriefReportsMailFailureWithoutFailingTheBrief() async throws {
        let calendarRuntime = InMemoryAgentCalendarRuntime()
        let tool = AttentionBriefTool(calendarRuntime: calendarRuntime, mailRuntime: StubMailRuntime(shouldThrow: true))

        let result = try await tool.execute(arguments: AgentToolArguments(values: [:]), context: Self.context(toolCallID: "brief-3"))

        let object = try #require(try Self.jsonObject(result) as? [String: Any])
        let mail = try #require(object["mail"] as? [String: Any])
        #expect(mail["status"] as? String == "failed")
    }

    @Test func attentionBriefSchemaIsArgumentFreeReadOnlyAndAlwaysExposed() throws {
        let tool = AttentionBriefTool(calendarRuntime: InMemoryAgentCalendarRuntime())
        #expect(tool.name == "attention_brief")
        #expect(tool.permission == .readCalendar)
        guard case .closedObject(let properties, let required) = tool.inputSchema else {
            Issue.record("attention_brief schema must be a closed object")
            return
        }
        #expect(required.isEmpty)
        #expect(properties["days"] != nil)
        // Unconditional exposure: no calendar/mail signals in the context.
        var registry = AgentToolRegistry()
        registry.register(tool)
        let definition = try #require(registry.definition(named: AttentionBriefTool.toolName))
        let policy = AgentRunTokenPolicy()
        let exposed = policy.exposedTools(
            from: [definition],
            request: AgentChatRequest(sessionID: "session-exposure", userMessage: "tell me a joke"),
            retrievalPlan: AgentRunRetrievalPlan(requiresCurrentTime: false, requiresContinuity: false, requiresNoteSearch: false, requiresFinalProfile: false),
            mode: .contextual
        )
        #expect(exposed.map(\.name) == ["attention_brief"])
    }

    private static func message(id: String, subject: String) -> MailMessageSummary {
        MailMessageSummary(
            id: MailMessageID(rawValue: id),
            accountID: MailAccountID(rawValue: "account-1"),
            mailboxID: MailMailboxID(rawValue: "inbox"),
            subject: subject,
            from: MailAddress(name: "Alice", email: "alice@example.com"),
            to: [MailAddress(email: "connor@example.com")],
            snippet: "Please pay by Friday."
        )
    }

    private static func context(toolCallID: String) -> AgentToolExecutionContext {
        AgentToolExecutionContext(
            runID: "run-attention-brief",
            sessionID: "session-attention-brief",
            groupID: "group-attention-brief",
            userPrompt: "test",
            toolCallID: toolCallID,
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll, auditLog: InMemoryAgentAuditLog())
        )
    }

    private static func jsonObject(_ result: AgentToolResult) throws -> Any {
        let json = try #require(result.contentJSON)
        return try JSONSerialization.jsonObject(with: Data(json.utf8))
    }
}

private actor StubMailRuntime: AgentMailRuntime {
    private let messages: [MailMessageSummary]
    private let shouldThrow: Bool
    private(set) var lastRecentRequest: MailRuntimeRecentMessagesRequestBridge?

    init(messages: [MailMessageSummary] = [], shouldThrow: Bool = false) {
        self.messages = messages
        self.shouldThrow = shouldThrow
    }

    struct StubFailure: Error {}

    func listAccounts(runID: String?, sessionID: String?) async throws -> [MailAccount] { [] }

    func searchMessages(_ request: MailRuntimeSearchRequestBridge, runID: String?, sessionID: String?) async throws -> [MailMessageSummary] {
        if shouldThrow { throw StubFailure() }
        return messages
    }

    func listRecentMessages(_ request: MailRuntimeRecentMessagesRequestBridge, runID: String?, sessionID: String?) async throws -> [MailMessageSummary] {
        if shouldThrow { throw StubFailure() }
        lastRecentRequest = request
        return messages
    }

    func getMessage(id: MailMessageID, includeBody: Bool, runID: String?, sessionID: String?) async throws -> MailMessageDetail {
        throw StubFailure()
    }

    func setReadState(messageIDs: [MailMessageID], isRead: Bool, runID: String?, sessionID: String?) async throws {}

    func sendDraft(draftID: MailDraftID, approved: Bool, runID: String?, sessionID: String?) async throws -> MailSendReceipt {
        throw StubFailure()
    }
}
