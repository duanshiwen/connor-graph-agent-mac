import Foundation
import ConnorGraphCore

public protocol AgentCalendarRuntime: Sendable {
    func listCalendars(runID: String?, sessionID: String?) async throws -> [CalendarCollection]
    func listEvents(calendarID: CalendarID?, runID: String?, sessionID: String?) async throws -> [CalendarEvent]
    func searchEvents(query: String, startDate: Date?, endDate: Date?, timePreset: String?, timeFilterMode: String?, timeSort: String?, limit: Int, runID: String?, sessionID: String?) async throws -> [CalendarEvent]
    func getEvent(id: CalendarEventID, runID: String?, sessionID: String?) async throws -> CalendarEvent?
    func mutate(_ request: CalendarMutationRequest) async throws -> CalendarMutationResult
}

public actor InMemoryAgentCalendarRuntime: AgentCalendarRuntime {
    private var calendars: [CalendarCollection]
    private var events: [CalendarEvent]

    public init(calendars: [CalendarCollection] = [], events: [CalendarEvent] = []) {
        self.calendars = calendars
        self.events = events
    }

    public func listCalendars(runID: String?, sessionID: String?) async throws -> [CalendarCollection] {
        calendars
    }

    public func listEvents(calendarID: CalendarID?, runID: String?, sessionID: String?) async throws -> [CalendarEvent] {
        let filtered = calendarID.map { id in events.filter { $0.calendarID == id } } ?? events
        return filtered.sorted { $0.start.date < $1.start.date }
    }

    public func searchEvents(query: String, startDate: Date?, endDate: Date?, timePreset: String?, timeFilterMode: String?, timeSort: String?, limit: Int = NativeSearchLimitPolicy.defaultSearchLimit, runID: String?, sessionID: String?) async throws -> [CalendarEvent] {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = ISO8601DateFormatter()
        var temporalFilter: NativeSearchTemporalFilter?
        if let timePreset, let preset = NativeSearchTimePreset(rawValue: timePreset) {
            temporalFilter = NativeSearchTimePresetResolver.resolve(preset)
            temporalFilter?.mode = NativeSearchTemporalFilterMode(rawValue: timeFilterMode ?? "") ?? .intervalOverlapsRange
        } else if startDate != nil || endDate != nil {
            temporalFilter = NativeSearchTemporalFilter(start: startDate, end: endDate, mode: .intervalOverlapsRange, timeFieldPreference: [.eventStartAt])
            if let mode = timeFilterMode.flatMap(NativeSearchTemporalFilterMode.init(rawValue:)) { temporalFilter?.mode = mode }
        }
        _ = formatter
        let filtered = events.filter { event in
            let temporal = NativeSearchTemporalMetadata(primaryTime: event.start.date, primaryTimeKind: .eventStartAt, updatedAt: event.updatedAt, eventStartAt: event.start.date, eventEndAt: event.end.date, timezoneIdentifier: event.start.timeZoneIdentifier, isAllDay: event.isAllDay)
            if let temporalFilter, !temporalFilter.contains(temporal, sourceKind: .calendar) { return false }
            guard !normalized.isEmpty else { return true }
            return event.title.lowercased().contains(normalized)
                || (event.notes?.lowercased().contains(normalized) ?? false)
                || (event.location?.lowercased().contains(normalized) ?? false)
                || event.attendees.contains { ($0.name?.lowercased().contains(normalized) ?? false) || ($0.email?.lowercased().contains(normalized) ?? false) }
        }
        let ascending = timeSort == "timeAscThenRelevance" || timeSort == "relevanceThenTimeAsc" || timeSort == nil
        let requestedLimit = NativeSearchLimitPolicy.clampSearchLimit(limit)
        return Array(filtered.sorted { ascending ? $0.start.date < $1.start.date : $0.start.date > $1.start.date }.prefix(requestedLimit))
    }

    public func getEvent(id: CalendarEventID, runID: String?, sessionID: String?) async throws -> CalendarEvent? {
        events.first { $0.id == id }
    }

    public func mutate(_ request: CalendarMutationRequest) async throws -> CalendarMutationResult {
        let request = try request.validated()
        switch request.operation {
        case .create:
            guard let draft = request.draft else { throw CalendarMutationError.invalidInput("draft is required") }
            if !calendars.isEmpty {
                guard let calendar = calendars.first(where: { $0.id == draft.calendarID }) else { throw CalendarMutationError.calendarNotFound(draft.calendarID) }
                guard !calendar.isReadOnly else { throw CalendarMutationError.readOnlyCollection(calendar.capabilities.readOnlyReason) }
            }
            let version = CalendarMutationVersion(value: UUID().uuidString)
            let event = CalendarEvent(id: CalendarEventID(rawValue: "event-\(UUID().uuidString)"), calendarID: draft.calendarID, title: draft.title, start: draft.start, end: draft.end, isAllDay: draft.isAllDay, location: draft.location, url: draft.url, notes: draft.notes, sourceMetadata: CalendarEventSourceMetadata(sourceKind: .macOSEventKit, etag: version.value))
            events.append(event)
            let receipt = CalendarWriteReceipt(mutationKind: .createEvent, eventID: event.id, approved: true, summary: "Created approved calendar event \(event.id.rawValue)")
            return CalendarMutationResult(receipt: receipt, confirmedEvent: event, remoteVersion: version)
        case .update:
            guard let eventID = request.eventID, let index = events.firstIndex(where: { $0.id == eventID }), let patch = request.patch else { throw CalendarMutationError.eventNotFound }
            guard events[index].sourceMetadata?.etag == request.expectedVersion?.value else { throw CalendarMutationError.conflict(expected: request.expectedVersion?.value, actual: events[index].sourceMetadata?.etag) }
            var event = events[index]
            apply(patch.title, to: &event.title)
            apply(patch.start, to: &event.start)
            apply(patch.end, to: &event.end)
            apply(patch.isAllDay, to: &event.isAllDay)
            applyOptional(patch.location, to: &event.location)
            applyOptional(patch.url, to: &event.url)
            applyOptional(patch.notes, to: &event.notes)
            guard event.end.date > event.start.date else { throw CalendarMutationError.invalidInput("end must be after start") }
            let version = CalendarMutationVersion(value: UUID().uuidString)
            event.sourceMetadata?.etag = version.value
            event.updatedAt = Date()
            events[index] = event
            let receipt = CalendarWriteReceipt(mutationKind: .updateEvent, eventID: event.id, approved: true, summary: "Updated approved calendar event \(event.id.rawValue)")
            return CalendarMutationResult(receipt: receipt, confirmedEvent: event, remoteVersion: version)
        case .delete:
            guard let eventID = request.eventID, let index = events.firstIndex(where: { $0.id == eventID }) else { throw CalendarMutationError.eventNotFound }
            guard events[index].sourceMetadata?.etag == request.expectedVersion?.value else { throw CalendarMutationError.conflict(expected: request.expectedVersion?.value, actual: events[index].sourceMetadata?.etag) }
            events.remove(at: index)
            let receipt = CalendarWriteReceipt(mutationKind: .deleteEvent, eventID: eventID, approved: true, summary: "Deleted approved calendar event \(eventID.rawValue)")
            return CalendarMutationResult(receipt: receipt)
        }
    }

    private func apply<Value>(_ patch: CalendarPatchValue<Value>, to value: inout Value) {
        if case .set(let replacement) = patch { value = replacement }
    }

    private func applyOptional<Value>(_ patch: CalendarPatchValue<Value>, to value: inout Value?) {
        switch patch {
        case .unchanged: break
        case .clear: value = nil
        case .set(let replacement): value = replacement
        }
    }
}

public struct CalendarSearchEventsTool: AgentTool {
    public let runtime: any AgentCalendarRuntime
    public let recorder: (any NativeSourceReferenceRecording)?
    public var name: String { "calendar_search_events" }
    public var description: String { "Search Connor-owned calendar events as candidate results; use calendar_read with operation get_event for selected event detail reads that should become Memory OS evidence." }
    public var permission: AgentPermissionCapability { .readCalendar }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "query": .string(description: "Search query; leave empty to search by time range only"),
            "startDate": .string(description: "Optional ISO-8601 inclusive start timestamp"),
            "endDate": .string(description: "Optional ISO-8601 exclusive end timestamp"),
            "timePreset": .string(description: "Optional time preset such as today, tomorrow, last7Days, last30Days, thisWeek, next7Days"),
            "timeFilterMode": .string(description: "Optional mode such as intervalOverlapsRange or startsInRange"),
            "timeSort": .string(description: "Optional sort: relevanceThenTimeDesc, relevanceThenTimeAsc, timeDescThenRelevance, timeAscThenRelevance"),
            "limit": .integer(description: "Maximum event details to return")
        ], required: [])
    }

    public init(runtime: any AgentCalendarRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        self.runtime = runtime
        self.recorder = recorder
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let formatter = ISO8601DateFormatter()
        let events = try await runtime.searchEvents(
            query: arguments.string("query") ?? "",
            startDate: arguments.string("startDate").flatMap { formatter.date(from: $0) },
            endDate: arguments.string("endDate").flatMap { formatter.date(from: $0) },
            timePreset: arguments.string("timePreset"),
            timeFilterMode: arguments.string("timeFilterMode"),
            timeSort: arguments.string("timeSort"),
            limit: NativeSearchLimitPolicy.clampSearchLimit(arguments.int("limit") ?? NativeSearchLimitPolicy.defaultSearchLimit),
            runID: context.runID,
            sessionID: context.sessionID
        )
        await recorder?.record(events.map { NativeSourceReference.calendarEvent($0, query: arguments.string("query"), strength: .summaryCandidate, toolName: name, context: context) })
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: CalendarEventCandidateTextRenderer.render(events, verb: "Found"), contentJSON: try ContactJSON.encode(events))
    }
}

public struct CalendarReadTool: AgentTool {
    public let runtime: any AgentCalendarRuntime
    public let recorder: (any NativeSourceReferenceRecording)?
    public var name: String { "calendar_read" }
    public var description: String { "Read Connor-owned calendar data using operations: list_calendars, list_events, get_event, get_agenda, get_free_busy." }
    public var permission: AgentPermissionCapability { .readCalendar }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "operation": .string(description: "list_calendars | list_events | get_event | get_agenda | get_free_busy"),
            "calendarID": .string(description: "Optional calendar ID"),
            "eventID": .string(description: "Optional event ID")
        ], required: ["operation"])
    }

    public init(runtime: any AgentCalendarRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        self.runtime = runtime
        self.recorder = recorder
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let operation = arguments.string("operation") ?? "list_events"
        switch operation {
        case "list_calendars":
            let calendars = try await runtime.listCalendars(runID: context.runID, sessionID: context.sessionID)
            let writable = calendars.filter { !$0.isReadOnly && $0.capabilities.canCreateEvents }
            let summary: String
            if writable.isEmpty {
                summary = "Listed \(calendars.count) calendars. No writable calendars are available for event creation."
            } else {
                let choices = writable.map { "\($0.displayName) [exact id: \($0.id.rawValue)]" }.joined(separator: "; ")
                summary = "Listed \(calendars.count) calendars; \(writable.count) writable for event creation: \(choices)"
            }
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: summary, contentJSON: try ContactJSON.encode(calendars))
        case "list_events", "get_agenda":
            let events = try await runtime.listEvents(calendarID: arguments.string("calendarID").map(CalendarID.init(rawValue:)), runID: context.runID, sessionID: context.sessionID)
            await recorder?.record(events.map { NativeSourceReference.calendarEvent($0, query: nil, strength: .summaryCandidate, toolName: name, context: context) })
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: CalendarEventCandidateTextRenderer.render(events, verb: "Listed"), contentJSON: try ContactJSON.encode(events))
        case "get_event":
            guard let eventID = arguments.string("eventID") else { throw AgentToolError.invalidArguments("eventID is required") }
            let event = try await runtime.getEvent(id: CalendarEventID(rawValue: eventID), runID: context.runID, sessionID: context.sessionID)
            if let event {
                await recorder?.record([NativeSourceReference.calendarEvent(event, query: nil, strength: .detailRead, toolName: name, context: context)])
                return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: CalendarEventDetailTextRenderer.render(event), contentJSON: try ContactJSON.encode(event))
            }
            let text = "Calendar event not found for eventID '\(eventID)'. Do not reuse or guess this ID. Search or list events again and copy a returned eventID exactly. Do not call calendar_write with this ID."
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: text, contentJSON: try ContactJSON.encode(event))
        case "get_free_busy":
            let events = try await runtime.listEvents(calendarID: arguments.string("calendarID").map(CalendarID.init(rawValue:)), runID: context.runID, sessionID: context.sessionID)
            let blocks = events.map { CalendarFreeBusyBlock(calendarID: $0.calendarID, start: $0.start.date, end: $0.end.date) }
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Computed \(blocks.count) free/busy blocks", contentJSON: try ContactJSON.encode(blocks))
        default:
            throw AgentToolError.invalidArguments("Unsupported calendar_read operation: \(operation)")
        }
    }
}

public struct CalendarWriteTool: AgentTool {
    public let runtime: any AgentCalendarRuntime
    public var name: String { "calendar_write" }
    public var description: String { "Create, update, or delete a non-recurring calendar event after trusted mutateCalendar approval. For create, first call calendar_read list_calendars and copy an exact writable calendar id; 'default', display names, and example IDs are not valid substitutes. Read the event first before update/delete and never overwrite a version conflict." }
    public var permission: AgentPermissionCapability { .mutateCalendar }
    public var inputExamples: [[String: SendableJSONValue]] {
        [
            [
                "operation": .string("create_event"),
                "calendarID": .string("exact-calendar-id-from-list-calendars"),
                "title": .string("Project review"),
                "start": .string("2026-07-12T02:00:00Z"),
                "end": .string("2026-07-12T03:00:00Z"),
                "isAllDay": .bool(false)
            ],
            [
                "operation": .string("update_event"),
                "eventID": .string("event-id-from-calendar-read"),
                "expectedVersion": .string("version-from-calendar-read"),
                "title": .string("Updated project review")
            ],
            [
                "operation": .string("delete_event"),
                "eventID": .string("event-id-from-calendar-read"),
                "expectedVersion": .string("version-from-calendar-read")
            ]
        ]
    }
    public var inputSchema: AgentToolInputSchema {
        .closedObject(properties: [
            "operation": .stringEnumeration(values: ["create_event", "update_event", "delete_event"], description: "Calendar mutation operation"),
            "calendarID": .string(description: "Exact writable calendar ID returned by calendar_read list_calendars; required for create_event"),
            "eventID": .string(description: "Exact event ID returned by calendar_read get_event; required for update_event and delete_event"),
            "expectedVersion": .string(description: "Exact version returned by the latest event read; required for update_event and delete_event"),
            "title": .string(description: "Event title"),
            "start": .string(description: "ISO-8601 start timestamp"),
            "end": .string(description: "ISO-8601 end timestamp"),
            "isAllDay": .boolean(description: "Whether this is an all-day event"),
            "location": .string(description: "Event location"),
            "url": .string(description: "Event URL"),
            "notes": .string(description: "Event notes"),
            "clearLocation": .boolean(description: "Clear the existing location on update"),
            "clearURL": .boolean(description: "Clear the existing URL on update"),
            "clearNotes": .boolean(description: "Clear the existing notes on update")
        ], required: ["operation"])
    }

    public init(runtime: any AgentCalendarRuntime) { self.runtime = runtime }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard context.approvedCapabilities.contains(.mutateCalendar) else { throw AgentToolError.permissionDenied("Calendar write requires trusted mutateCalendar approval") }
        let formatter = ISO8601DateFormatter()
        guard let operation = arguments.string("operation") else {
            throw AgentToolError.invalidArguments("Missing required calendar_write argument: operation. Use create_event, update_event, or delete_event.")
        }
        let request: CalendarMutationRequest
        switch operation {
        case "create_event":
            let requiredKeys = ["calendarID", "title", "start", "end"]
            let missingKeys = requiredKeys.filter { arguments.string($0) == nil }
            guard missingKeys.isEmpty else {
                throw AgentToolError.invalidArguments("Missing required create_event arguments: \(missingKeys.joined(separator: ", ")). Required fields are calendarID, title, start, end. Call calendar_read with operation list_calendars first and use an exact writable calendarID.")
            }
            let calendarID = arguments.string("calendarID")!
            let title = arguments.string("title")!
            let startText = arguments.string("start")!
            let endText = arguments.string("end")!
            guard let start = formatter.date(from: startText) else { throw AgentToolError.invalidArguments("Invalid ISO-8601 start timestamp: \(startText)") }
            guard let end = formatter.date(from: endText) else { throw AgentToolError.invalidArguments("Invalid ISO-8601 end timestamp: \(endText)") }
            request = CalendarMutationRequest(operation: .create, draft: CalendarEventDraft(calendarID: CalendarID(rawValue: calendarID), title: title, start: CalendarEventDateTime(date: start), end: CalendarEventDateTime(date: end), isAllDay: arguments.bool("isAllDay") ?? false, location: arguments.string("location"), url: arguments.string("url").flatMap(URL.init(string:)), notes: arguments.string("notes")), runID: context.runID, sessionID: context.sessionID)
        case "update_event":
            let missingKeys = ["eventID", "expectedVersion"].filter { arguments.string($0) == nil }
            guard missingKeys.isEmpty else { throw AgentToolError.invalidArguments("Missing required update_event arguments: \(missingKeys.joined(separator: ", ")). Required fields are eventID, expectedVersion.") }
            let eventID = arguments.string("eventID")!
            let expectedVersion = arguments.string("expectedVersion")!
            if let startText = arguments.string("start"), formatter.date(from: startText) == nil { throw AgentToolError.invalidArguments("Invalid ISO-8601 start timestamp: \(startText)") }
            if let endText = arguments.string("end"), formatter.date(from: endText) == nil { throw AgentToolError.invalidArguments("Invalid ISO-8601 end timestamp: \(endText)") }
            request = CalendarMutationRequest(operation: .update, eventID: CalendarEventID(rawValue: eventID), expectedVersion: CalendarMutationVersion(value: expectedVersion), patch: CalendarEventPatch(title: arguments.string("title").map(CalendarPatchValue.set) ?? .unchanged, start: datePatch("start", arguments: arguments, formatter: formatter), end: datePatch("end", arguments: arguments, formatter: formatter), isAllDay: arguments.bool("isAllDay").map(CalendarPatchValue.set) ?? .unchanged, location: optionalPatch(value: arguments.string("location"), clear: arguments.bool("clearLocation") == true), url: optionalPatch(value: arguments.string("url").flatMap(URL.init(string:)), clear: arguments.bool("clearURL") == true), notes: optionalPatch(value: arguments.string("notes"), clear: arguments.bool("clearNotes") == true)), runID: context.runID, sessionID: context.sessionID)
        case "delete_event":
            let missingKeys = ["eventID", "expectedVersion"].filter { arguments.string($0) == nil }
            guard missingKeys.isEmpty else { throw AgentToolError.invalidArguments("Missing required delete_event arguments: \(missingKeys.joined(separator: ", ")). Required fields are eventID, expectedVersion.") }
            request = CalendarMutationRequest(operation: .delete, eventID: CalendarEventID(rawValue: arguments.string("eventID")!), expectedVersion: CalendarMutationVersion(value: arguments.string("expectedVersion")!), runID: context.runID, sessionID: context.sessionID)
        default:
            throw AgentToolError.invalidArguments("Unsupported calendar_write operation '\(String(operation.prefix(80)))'. Use create_event, update_event, or delete_event.")
        }
        do {
            let result = try await runtime.mutate(request.validated())
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: result.receipt.summary, contentJSON: try ContactJSON.encode(result))
        } catch let error as AgentToolError { throw error }
        catch let error as CalendarMutationError { throw mapCalendarMutationError(error) }
        catch { throw AgentToolError.invalidArguments("Calendar mutation failed: \(error.localizedDescription)") }
    }

    private func mapCalendarMutationError(_ error: CalendarMutationError) -> AgentToolError {
        switch error {
        case .invalidInput(let message):
            return .invalidArguments(message)
        case .calendarNotFound(let calendarID):
            return .invalidArguments("Calendar '\(calendarID.rawValue)' was not found. Do not use 'default', display names, or example IDs as calendarID. Call calendar_read with operation list_calendars, select a calendar whose capabilities.canCreateEvents is true and isReadOnly is false, then retry with its exact id.")
        case .accountNotFound(let accountID):
            return .invalidArguments("The account '\(accountID.rawValue)' for the selected calendar was not found. Refresh calendar sources, call calendar_read with operation list_calendars, and retry with an exact current calendar id.")
        case .eventNotFound:
            return .invalidArguments("The calendar event was not found. For update_event or delete_event, call calendar_read with operation get_event and retry with the exact current eventID and expectedVersion.")
        case .readOnlySource:
            return .permissionDenied("The selected calendar source is read-only or bidirectional writes are disabled.")
        case .readOnlyCollection(let reason):
            return .permissionDenied("The selected calendar is read-only\(reason.map { ": \($0)" } ?? ".")")
        case .recurrenceUnsupported:
            return .invalidArguments("Recurring calendar events are not supported for mutation. No write was performed.")
        case .schedulingUnsupported:
            return .invalidArguments("Events with organizer, attendee, invitation, or scheduling semantics are not supported for mutation. No write was performed.")
        case .conflict(let expected, let actual):
            return .invalidArguments("Calendar event version conflict (expected: \(expected ?? "missing"), actual: \(actual ?? "missing")). Read the event again and do not overwrite the conflict automatically.")
        case .authenticationRequired:
            return .permissionDenied("Calendar authentication is required. Reconnect the calendar source before retrying.")
        case .permissionDenied:
            return .permissionDenied("The calendar provider denied this mutation.")
        case .remoteFailure(let message):
            return .invalidArguments("The calendar provider failed the mutation: \(message)")
        case .verificationFailed:
            return .invalidArguments("The remote calendar write could not be verified locally. Refresh the calendar before retrying.")
        }
    }

    private func datePatch(_ key: String, arguments: AgentToolArguments, formatter: ISO8601DateFormatter) -> CalendarPatchValue<CalendarEventDateTime> {
        guard let text = arguments.string(key), let date = formatter.date(from: text) else { return .unchanged }
        return .set(CalendarEventDateTime(date: date))
    }

    private func optionalPatch<Value>(value: Value?, clear: Bool) -> CalendarPatchValue<Value> where Value: Codable & Sendable & Equatable & Hashable {
        if clear { return .clear }
        return value.map(CalendarPatchValue.set) ?? .unchanged
    }
}

private enum CalendarEventDetailTextRenderer {
    static func render(_ event: CalendarEvent) -> String {
        let formatter = ISO8601DateFormatter()
        let eligibility = mutationEligibility(event)
        let version = event.sourceMetadata?.etag
        let ready = eligibility == "eligible" && version?.isEmpty == false
        var lines = [
            ready ? "Loaded mutation-ready calendar event." : "Loaded calendar event; it is not mutation-ready.",
            "eventID: \(event.id.rawValue)",
            "calendarID: \(event.calendarID.rawValue)",
            "expectedVersion: \(version?.isEmpty == false ? version! : "unavailable")",
            "title: \(event.title)",
            "start: \(formatter.string(from: event.start.date))",
            "end: \(formatter.string(from: event.end.date))",
            "isAllDay: \(event.isAllDay)",
            "mutationEligibility: \(version?.isEmpty == false ? eligibility : "version-unavailable")"
        ]
        if ready {
            lines.append("For update_event or delete_event, copy eventID and expectedVersion exactly. Do not use calendarID as eventID.")
        } else {
            lines.append("Do not call calendar_write for this event until a fresh detail read reports mutationEligibility: eligible and an exact expectedVersion.")
        }
        return lines.joined(separator: "\n")
    }
}

private func mutationEligibility(_ event: CalendarEvent) -> String {
    if event.sourceMetadata?.isRecurring == true || event.recurrenceSummary != nil { return "recurring" }
    if event.sourceMetadata?.hasAttendees == true || !event.attendees.isEmpty || event.sourceMetadata?.organizerEmail != nil || event.sourceMetadata?.scheduleTag != nil { return "scheduling" }
    return "eligible"
}

private enum CalendarEventCandidateTextRenderer {
    static func render(_ events: [CalendarEvent], verb: String) -> String {
        guard !events.isEmpty else {
            return "\(verb) 0 calendar event candidates. Adjust the query or time range and search again; do not guess an eventID."
        }
        let formatter = ISO8601DateFormatter()
        let noun = events.count == 1 ? "candidate" : "candidates"
        let rows = events.enumerated().map { index, event in
            """
            \(index + 1). title: \(event.title)
               eventID: \(event.id.rawValue)
               calendarID: \(event.calendarID.rawValue)
               start: \(formatter.string(from: event.start.date))
               end: \(formatter.string(from: event.end.date))
               isAllDay: \(event.isAllDay)
               mutationEligibility: \(eligibility(event))
            """
        }.joined(separator: "\n")
        return "\(verb) \(events.count) calendar event \(noun).\n\n\(rows)\n\nNext: call calendar_read with operation get_event and copy eventID exactly."
    }

    private static func eligibility(_ event: CalendarEvent) -> String { mutationEligibility(event) }
}

public extension AgentToolRegistry {
    mutating func registerNativeCalendarTools(runtime: any AgentCalendarRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        register(CalendarSearchEventsTool(runtime: runtime, recorder: recorder))
        register(CalendarReadTool(runtime: runtime, recorder: recorder))
        register(CalendarWriteTool(runtime: runtime))
    }
}
