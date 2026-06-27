import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Suite("Calendar Contacts Agent Tools Tests")
struct CalendarContactsAgentToolsTests {
    @Test func timeAnalyzeRangesToolComputesOverlapJSON() async throws {
        let tool = TimeAnalyzeRangesTool()
        let call = AgentToolCall(
            id: "call-time",
            name: "time_analyze_ranges",
            argumentsJSON: """
            {
              "ranges": [
                {"id":"a","start":"2026-06-19T06:00:00Z","end":"2026-06-19T07:00:00Z"},
                {"id":"b","start":"2026-06-19T06:30:00Z","end":"2026-06-19T08:00:00Z"}
              ]
            }
            """
        )
        let result = try await tool.execute(arguments: try AgentToolArguments(json: call.argumentsJSON), context: Self.context(toolCallID: call.id))

        #expect(result.toolName == "time_analyze_ranges")
        #expect(result.contentText.contains("Analyzed 2 time ranges"))
        #expect(result.contentJSON?.contains("overlapSeconds") == true)
    }

    @Test func calendarReadToolListsEventsFromRuntime() async throws {
        let runtime = InMemoryAgentCalendarRuntime(events: [Self.sampleEvent])
        let tool = CalendarReadTool(runtime: runtime)
        let result = try await tool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"list_events\"}"),
            context: Self.context(toolCallID: "call-calendar-read")
        )

        #expect(result.toolName == "calendar_read")
        #expect(result.contentText.contains("Listed 1 calendar event candidates"))
        #expect(result.contentJSON?.contains("产品讨论") == true)
    }

    @Test func calendarSearchEventsToolDescribesCandidatesAndSelectedDetailReads() {
        let tool = CalendarSearchEventsTool(runtime: InMemoryAgentCalendarRuntime())

        #expect(tool.description.contains("candidate"))
        #expect(tool.description.contains("calendar_read"))
        #expect(tool.description.contains("get_event"))
        #expect(!tool.description.contains("no separate calendar detail fetch is needed"))
        #expect(!tool.description.contains("return full event details directly"))
    }

    @Test func calendarSearchEventsToolReturnsEventCandidatesWithDetailsInForegroundResult() async throws {
        let event = CalendarEvent(
            id: CalendarEventID(rawValue: "event-design-review"),
            calendarID: CalendarID(rawValue: "calendar-work"),
            title: "Memory OS 设计评审",
            start: CalendarEventDateTime(date: Date(timeIntervalSince1970: 2_000)),
            end: CalendarEventDateTime(date: Date(timeIntervalSince1970: 5_600)),
            location: "会议室 A",
            notes: "讨论 RSS 和浏览历史工具暴露",
            attendees: [CalendarAttendee(id: CalendarAttendeeID(rawValue: "attendee-1"), name: "诗闻", email: "shiwen@example.com")]
        )
        let runtime = InMemoryAgentCalendarRuntime(events: [event])
        let tool = CalendarSearchEventsTool(runtime: runtime)
        let result = try await tool.execute(
            arguments: try AgentToolArguments(json: "{\"query\":\"RSS\",\"limit\":10}"),
            context: Self.context(toolCallID: "call-calendar-search")
        )

        #expect(result.toolName == "calendar_search_events")
        #expect(result.contentText.contains("calendar event candidates"))
        #expect(result.contentJSON?.contains("Memory OS 设计评审") == true)
        #expect(result.contentJSON?.contains("会议室 A") == true)
        #expect(result.contentJSON?.contains("shiwen@example.com") == true)
    }

    @Test func calendarWriteToolIsCurrentlyDisabledEvenWithApproval() async throws {
        let runtime = InMemoryAgentCalendarRuntime(events: [])
        let tool = CalendarWriteTool(runtime: runtime)

        var deniedCalendarWrite = false
        do {
            _ = try await tool.execute(
                arguments: try AgentToolArguments(json: "{\"operation\":\"create_event\",\"title\":\"新日程\",\"calendarID\":\"calendar-work\",\"start\":\"2026-06-19T06:00:00Z\",\"end\":\"2026-06-19T07:00:00Z\",\"approved\":true}"),
                context: Self.context(toolCallID: "call-calendar-write-disabled")
            )
        } catch AgentToolError.permissionDenied(let message) {
            deniedCalendarWrite = message.contains("暂不支持")
        }
        #expect(deniedCalendarWrite)
    }

    @Test func contactsReadAndWriteToolsUseAggregatedOperations() async throws {
        let runtime = InMemoryAgentContactRuntime(contacts: [ContactRecord(id: MailContactID(rawValue: "shiwen"), givenName: "诗闻", emails: [ContactEmailAddress(email: "shiwen@example.com")])])
        let readTool = ContactsReadTool(runtime: runtime)
        let writeTool = ContactsWriteTool(runtime: runtime)

        let found = try await readTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"search_contacts\",\"query\":\"shiwen\"}"),
            context: Self.context(toolCallID: "call-contacts-read")
        )
        #expect(found.toolName == "contacts_read")
        #expect(found.contentText.contains("Found 1 contacts"))

        var deniedContactWrite = false
        do {
            _ = try await writeTool.execute(
                arguments: try AgentToolArguments(json: "{\"operation\":\"create_contact\",\"email\":\"alice@example.com\",\"name\":\"Alice\",\"approved\":false}"),
                context: Self.context(toolCallID: "call-contacts-write-denied")
            )
        } catch AgentToolError.permissionDenied(_) {
            deniedContactWrite = true
        }
        #expect(deniedContactWrite)

        let created = try await writeTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"create_contact\",\"email\":\"alice@example.com\",\"name\":\"Alice\",\"approved\":true}"),
            context: Self.context(toolCallID: "call-contacts-write-approved")
        )
        #expect(created.toolName == "contacts_write")
        #expect(created.contentText.contains("Created approved contact"))
    }

    @Test func registryRegistersCalendarContactsAndTimeTools() {
        var registry = AgentToolRegistry()
        registry.registerTimeAnalysisTool()
        registry.registerNativeCalendarTools(runtime: InMemoryAgentCalendarRuntime())
        registry.registerNativeContactsAggregateTools(runtime: InMemoryAgentContactRuntime())

        let names = Set(registry.definitions.map(\.name))
        #expect(names.contains("time_analyze_ranges"))
        #expect(names.contains("calendar_search_events"))
        #expect(names.contains("calendar_read"))
        #expect(names.contains("calendar_write"))
        #expect(names.contains("contacts_read"))
        #expect(names.contains("contacts_write"))
    }

    private static func context(toolCallID: String) -> AgentToolExecutionContext {
        let audit = InMemoryAgentAuditLog()
        let policy = AgentPolicyEngine(permissionMode: .allowAll, auditLog: audit)
        return AgentToolExecutionContext(
            runID: "run-calendar-contacts",
            sessionID: "session-calendar-contacts",
            groupID: "group-calendar-contacts",
            userPrompt: "test",
            toolCallID: toolCallID,
            policyEngine: policy
        )
    }

    private static var sampleEvent: CalendarEvent {
        CalendarEvent(
            id: CalendarEventID(rawValue: "event-1"),
            calendarID: CalendarID(rawValue: "calendar-work"),
            title: "产品讨论",
            start: CalendarEventDateTime(date: Date(timeIntervalSince1970: 1_000)),
            end: CalendarEventDateTime(date: Date(timeIntervalSince1970: 4_600))
        )
    }
}
