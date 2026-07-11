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

    @Test func calendarReadToolSummarizesExactWritableCalendarIDs() async throws {
        let writable = CalendarCollection(id: .init(rawValue: "calendar-exact-write-id"), accountID: .init(rawValue: "account"), displayName: "Work")
        let readOnly = CalendarCollection(id: .init(rawValue: "calendar-holidays"), accountID: .init(rawValue: "account"), displayName: "Holidays", isReadOnly: true, capabilities: .init(canCreateEvents: false, canUpdateEvents: false, canDeleteEvents: false, supportsScheduling: false, readOnlyReason: "subscription"))
        let tool = CalendarReadTool(runtime: InMemoryAgentCalendarRuntime(calendars: [writable, readOnly]))
        let result = try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"list_calendars\"}"), context: Self.context(toolCallID: "call-list-calendars"))

        #expect(result.contentText.contains("1 writable"))
        #expect(result.contentText.contains("Work"))
        #expect(result.contentText.contains("calendar-exact-write-id"))
        #expect(!result.contentText.contains("calendar-holidays"))
        #expect(result.contentJSON?.contains("calendar-holidays") == true)
    }

    @Test func calendarReadToolReportsWhenNoWritableCalendarExists() async throws {
        let readOnly = CalendarCollection(id: .init(rawValue: "calendar-holidays"), accountID: .init(rawValue: "account"), displayName: "Holidays", isReadOnly: true)
        let tool = CalendarReadTool(runtime: InMemoryAgentCalendarRuntime(calendars: [readOnly]))
        let result = try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"list_calendars\"}"), context: Self.context(toolCallID: "call-list-read-only-calendars"))

        #expect(result.contentText.contains("No writable calendars"))
    }

    @Test func calendarReadToolListsEventsFromRuntime() async throws {
        let runtime = InMemoryAgentCalendarRuntime(events: [Self.sampleEvent])
        let tool = CalendarReadTool(runtime: runtime)
        let result = try await tool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"list_events\"}"),
            context: Self.context(toolCallID: "call-calendar-read")
        )

        #expect(result.toolName == "calendar_read")
        #expect(result.contentText.contains("Listed 1 calendar event candidate"))
        #expect(result.contentText.contains("eventID: event-1"))
        #expect(result.contentText.contains("calendarID: calendar-work"))
        #expect(result.contentText.contains("title: 产品讨论"))
        #expect(result.contentText.contains("start: 1970-01-01T00:16:40Z"))
        #expect(result.contentText.contains("end: 1970-01-01T01:16:40Z"))
        #expect(result.contentText.contains("Next: call calendar_read with operation get_event"))
        #expect(result.contentJSON?.contains("产品讨论") == true)
    }

    @Test func calendarAgendaExposesExactOpaqueCandidateIDsWithoutNotes() async throws {
        let opaqueID = "467EBD97-A2D1-49CC-8EE6-BE7136D0BD70:8BCA05B8/765F-44BD"
        let event = CalendarEvent(
            id: .init(rawValue: opaqueID),
            calendarID: .init(rawValue: "caldav-https://calendar.example.test/users/shiwen/"),
            title: "训练安排",
            start: .init(date: Date(timeIntervalSince1970: 1_000)),
            end: .init(date: Date(timeIntervalSince1970: 4_600)),
            notes: "PRIVATE-LONG-NOTES-SHOULD-NOT-ENTER-CANDIDATE-TEXT"
        )
        let result = try await CalendarReadTool(runtime: InMemoryAgentCalendarRuntime(events: [event])).execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"get_agenda\"}"),
            context: Self.context(toolCallID: "call-calendar-agenda")
        )

        #expect(result.contentText.contains(opaqueID))
        #expect(result.contentText.contains("caldav-https://calendar.example.test/users/shiwen/"))
        #expect(!result.contentText.contains("PRIVATE-LONG-NOTES"))
        #expect(result.contentJSON?.contains("PRIVATE-LONG-NOTES") == true)
    }

    @Test func calendarReadGetEventReturnsMutationReadyIdentityAndVersion() async throws {
        let event = CalendarEvent(
            id: .init(rawValue: "event:opaque/id"),
            calendarID: .init(rawValue: "calendar-work"),
            title: "产品讨论",
            start: .init(date: Date(timeIntervalSince1970: 1_000)),
            end: .init(date: Date(timeIntervalSince1970: 4_600)),
            sourceMetadata: .init(sourceKind: .genericCalDAV, remoteIdentifier: "remote-event", etag: "W/\"etag-42\"")
        )
        let tool = CalendarReadTool(runtime: InMemoryAgentCalendarRuntime(events: [event]))
        let result = try await tool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"get_event\",\"eventID\":\"event:opaque/id\"}"),
            context: Self.context(toolCallID: "call-calendar-detail")
        )

        #expect(result.contentText.contains("Loaded mutation-ready calendar event"))
        #expect(result.contentText.contains("eventID: event:opaque/id"))
        #expect(result.contentText.contains("calendarID: calendar-work"))
        #expect(result.contentText.contains("expectedVersion: W/\"etag-42\""))
        #expect(result.contentText.contains("mutationEligibility: eligible"))
        #expect(result.contentText.contains("copy eventID and expectedVersion exactly"))
        #expect(result.contentJSON?.contains("etag-42") == true)
    }

    @Test func calendarReadGetEventExplainsIneligibleAndMissingEvents() async throws {
        let recurring = CalendarEvent(
            id: .init(rawValue: "event-recurring"),
            calendarID: .init(rawValue: "calendar-work"),
            title: "Recurring",
            start: .init(date: Date(timeIntervalSince1970: 1_000)),
            end: .init(date: Date(timeIntervalSince1970: 4_600)),
            recurrenceSummary: .init(ruleDescription: "FREQ=WEEKLY"),
            sourceMetadata: .init(sourceKind: .macOSEventKit, etag: "42", isRecurring: true)
        )
        let tool = CalendarReadTool(runtime: InMemoryAgentCalendarRuntime(events: [recurring]))
        let ineligible = try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"get_event\",\"eventID\":\"event-recurring\"}"), context: Self.context(toolCallID: "call-calendar-recurring"))
        #expect(ineligible.contentText.contains("mutationEligibility: recurring"))
        #expect(!ineligible.contentText.contains("Loaded mutation-ready"))

        let missing = try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"get_event\",\"eventID\":\"guessed-id\"}"), context: Self.context(toolCallID: "call-calendar-missing"))
        #expect(missing.contentText.contains("Calendar event not found for eventID 'guessed-id'"))
        #expect(missing.contentText.contains("Do not reuse or guess this ID"))
        #expect(missing.contentText.contains("Do not call calendar_write with this ID"))
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
        #expect(result.contentText.contains("calendar event candidate"))
        #expect(result.contentText.contains("eventID: event-design-review"))
        #expect(result.contentText.contains("calendarID: calendar-work"))
        #expect(result.contentText.contains("title: Memory OS 设计评审"))
        #expect(result.contentText.contains("mutationEligibility: scheduling"))
        #expect(!result.contentText.contains("讨论 RSS 和浏览历史工具暴露"))
        #expect(!result.contentText.contains("shiwen@example.com"))
        #expect(result.contentJSON?.contains("Memory OS 设计评审") == true)
        #expect(result.contentJSON?.contains("会议室 A") == true)
        #expect(result.contentJSON?.contains("shiwen@example.com") == true)
    }

    @Test func calendarWriteExamplesCannotBeMistakenForRealCalendarIDs() {
        let tool = CalendarWriteTool(runtime: InMemoryAgentCalendarRuntime())
        #expect(tool.description.contains("default"))
        #expect(tool.description.contains("example IDs"))
        #expect(tool.description.contains("exact"))
        #expect(tool.inputExamples.first?["calendarID"] == .string("exact-calendar-id-from-list-calendars"))
        #expect(tool.inputExamples.first?["calendarID"] != .string("calendar-work"))
    }

    @Test func calendarWriteSchemaConstrainsOperationAndExtraProperties() throws {
        let schema = CalendarWriteTool(runtime: InMemoryAgentCalendarRuntime()).inputSchema.jsonObject
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect(schema["required"] as? [String] == ["operation"])
        let properties = try #require(schema["properties"] as? [String: Any])
        let operation = try #require(properties["operation"] as? [String: Any])
        #expect(operation["enum"] as? [String] == ["create_event", "update_event", "delete_event"])
    }

    @Test func calendarWriteReportsActionableOperationErrors() async throws {
        let tool = CalendarWriteTool(runtime: InMemoryAgentCalendarRuntime())
        let context = Self.context(toolCallID: "call-calendar-invalid-operation").approving(.mutateCalendar)

        await Self.expectInvalidArguments(
            containing: "Missing required calendar_write argument: operation",
            executing: { try await tool.execute(arguments: try AgentToolArguments(json: "{\"title\":\"新日程\"}"), context: context) }
        )
        await Self.expectInvalidArguments(
            containing: "Unsupported calendar_write operation 'move_event'",
            executing: { try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"move_event\"}"), context: context) }
        )
    }

    @Test func calendarWriteReportsCreateFieldAndTimestampErrors() async throws {
        let tool = CalendarWriteTool(runtime: InMemoryAgentCalendarRuntime())
        let context = Self.context(toolCallID: "call-calendar-invalid-create").approving(.mutateCalendar)

        await Self.expectInvalidArguments(
            containing: "calendarID, title, start, end",
            executing: { try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"create_event\"}"), context: context) }
        )
        await Self.expectInvalidArguments(
            containing: "Call calendar_read with operation list_calendars",
            executing: { try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"create_event\"}"), context: context) }
        )
        await Self.expectInvalidArguments(
            containing: "Invalid ISO-8601 start timestamp",
            executing: { try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"create_event\",\"calendarID\":\"c\",\"title\":\"Bad\",\"start\":\"tomorrow\",\"end\":\"2026-06-19T07:00:00Z\"}"), context: context) }
        )
    }

    @Test func calendarWriteExplainsHowToRecoverFromUnknownCalendarID() async throws {
        let tool = CalendarWriteTool(runtime: FailingCalendarRuntime(error: .calendarNotFound(.init(rawValue: "default"))))
        let context = Self.context(toolCallID: "call-calendar-unknown").approving(.mutateCalendar)
        let arguments = try AgentToolArguments(json: "{\"operation\":\"create_event\",\"calendarID\":\"default\",\"title\":\"Test\",\"start\":\"2026-07-12T01:30:00Z\",\"end\":\"2026-07-12T02:00:00Z\"}")

        await Self.expectInvalidArguments(containing: "Calendar 'default' was not found", executing: { try await tool.execute(arguments: arguments, context: context) })
        await Self.expectInvalidArguments(containing: "calendar_read with operation list_calendars", executing: { try await tool.execute(arguments: arguments, context: context) })
        await Self.expectInvalidArguments(containing: "Do not use 'default', display names, or example IDs", executing: { try await tool.execute(arguments: arguments, context: context) })
    }

    @Test func calendarWriteReportsUpdateAndDeleteRequiredFields() async throws {
        let tool = CalendarWriteTool(runtime: InMemoryAgentCalendarRuntime())
        let context = Self.context(toolCallID: "call-calendar-invalid-mutation").approving(.mutateCalendar)

        await Self.expectInvalidArguments(
            containing: "eventID, expectedVersion",
            executing: { try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"update_event\"}"), context: context) }
        )
        await Self.expectInvalidArguments(
            containing: "eventID, expectedVersion",
            executing: { try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"delete_event\"}"), context: context) }
        )
    }

    @Test func calendarWriteRequiresTrustedExecutionApproval() async throws {
        let tool = CalendarWriteTool(runtime: InMemoryAgentCalendarRuntime())
        await #expect(throws: AgentToolError.self) {
            try await tool.execute(
                arguments: try AgentToolArguments(json: "{\"operation\":\"create_event\",\"title\":\"新日程\",\"calendarID\":\"calendar-work\",\"start\":\"2026-06-19T06:00:00Z\",\"end\":\"2026-06-19T07:00:00Z\",\"approved\":true}"),
                context: Self.context(toolCallID: "call-calendar-untrusted")
            )
        }
    }

    @Test func calendarWriteCreatesUpdatesAndDeletesWithTrustedApproval() async throws {
        let runtime = InMemoryAgentCalendarRuntime(calendars: [CalendarCollection(id: .init(rawValue: "calendar-work"), accountID: .init(rawValue: "account"), displayName: "Work")])
        let tool = CalendarWriteTool(runtime: runtime)
        let context = Self.context(toolCallID: "call-calendar-write").approving(.mutateCalendar)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let created = try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"create_event\",\"title\":\"新日程\",\"calendarID\":\"calendar-work\",\"start\":\"2026-06-19T06:00:00Z\",\"end\":\"2026-06-19T07:00:00Z\",\"location\":\"杭州\"}"), context: context)
        let createResult = try #require(created.contentJSON).data(using: .utf8).map { try decoder.decode(CalendarMutationResult.self, from: $0) }
        let eventID = try #require(createResult?.confirmedEvent?.id.rawValue)
        let version = try #require(createResult?.remoteVersion?.value)
        let updated = try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"update_event\",\"eventID\":\"\(eventID)\",\"expectedVersion\":\"\(version)\",\"title\":\"调整后的日程\",\"clearLocation\":true}"), context: context)
        #expect(updated.contentJSON?.contains("调整后的日程") == true)
        let updatedJSON = try #require(updated.contentJSON)
        let updateResult = try decoder.decode(CalendarMutationResult.self, from: Data(updatedJSON.utf8))
        let newVersion = try #require(updateResult.remoteVersion?.value)
        let deleted = try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"delete_event\",\"eventID\":\"\(eventID)\",\"expectedVersion\":\"\(newVersion)\"}"), context: context)
        #expect(deleted.contentText.contains("Deleted"))
        #expect(try await runtime.getEvent(id: .init(rawValue: eventID), runID: nil, sessionID: nil) == nil)
    }

    @Test func calendarWriteRejectsInvalidTimeRangeAndEmptyPatch() async throws {
        let tool = CalendarWriteTool(runtime: InMemoryAgentCalendarRuntime())
        let context = Self.context(toolCallID: "call-calendar-invalid").approving(.mutateCalendar)
        await #expect(throws: AgentToolError.self) {
            try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"create_event\",\"title\":\"Bad\",\"calendarID\":\"c\",\"start\":\"2026-06-19T08:00:00Z\",\"end\":\"2026-06-19T07:00:00Z\"}"), context: context)
        }
        await #expect(throws: AgentToolError.self) {
            try await tool.execute(arguments: try AgentToolArguments(json: "{\"operation\":\"update_event\",\"eventID\":\"e\",\"expectedVersion\":\"v\"}"), context: context)
        }
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

    @Test func contactsToolsDocumentStructuredPersonReferenceIDs() {
        let readTool = ContactsReadTool(runtime: InMemoryAgentContactRuntime())
        let writeTool = ContactsWriteTool(runtime: InMemoryAgentContactRuntime())

        #expect(readTool.description.contains("Referenced People"))
        #expect(readTool.description.contains("person_id"))
        #expect(readTool.description.contains("do not guess IDs from display names"))
        #expect(writeTool.description.contains("Referenced People"))
        #expect(writeTool.description.contains("never guess IDs from display names"))

        guard case .object(let readProperties, _) = readTool.inputSchema,
              case .string(let readIDDescription) = readProperties["id"],
              case .object(let writeProperties, _) = writeTool.inputSchema,
              case .string(let writeIDDescription) = writeProperties["id"] else {
            Issue.record("Expected contacts tools to expose object schemas with id descriptions")
            return
        }

        #expect(readIDDescription.contains("person_id from Referenced People"))
        #expect(readIDDescription.contains("do not infer"))
        #expect(writeIDDescription.contains("person_id from Referenced People"))
        #expect(writeIDDescription.contains("never inferred"))
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

    private static func expectInvalidArguments(
        containing expectedText: String,
        executing operation: () async throws -> AgentToolResult
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected invalid calendar arguments")
        } catch AgentToolError.invalidArguments(let message) {
            #expect(message.contains(expectedText))
        } catch {
            Issue.record("Expected invalidArguments, got \(error)")
        }
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

private struct FailingCalendarRuntime: AgentCalendarRuntime {
    let error: CalendarMutationError
    func listCalendars(runID: String?, sessionID: String?) async throws -> [CalendarCollection] { [] }
    func listEvents(calendarID: CalendarID?, runID: String?, sessionID: String?) async throws -> [CalendarEvent] { [] }
    func searchEvents(query: String, startDate: Date?, endDate: Date?, timePreset: String?, timeFilterMode: String?, timeSort: String?, limit: Int, runID: String?, sessionID: String?) async throws -> [CalendarEvent] { [] }
    func getEvent(id: CalendarEventID, runID: String?, sessionID: String?) async throws -> CalendarEvent? { nil }
    func mutate(_ request: CalendarMutationRequest) async throws -> CalendarMutationResult { throw error }
}
