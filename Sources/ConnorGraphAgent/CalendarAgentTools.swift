import Foundation
import ConnorGraphCore

public protocol AgentCalendarRuntime: Sendable {
    func listCalendars(runID: String?, sessionID: String?) async throws -> [CalendarCollection]
    func listEvents(calendarID: CalendarID?, runID: String?, sessionID: String?) async throws -> [CalendarEvent]
    func searchEvents(query: String, startDate: Date?, endDate: Date?, timePreset: String?, timeFilterMode: String?, timeSort: String?, limit: Int, runID: String?, sessionID: String?) async throws -> [CalendarEvent]
    func getEvent(id: CalendarEventID, runID: String?, sessionID: String?) async throws -> CalendarEvent?
    func createEvent(calendarID: CalendarID, title: String, start: Date, end: Date, approved: Bool, runID: String?, sessionID: String?) async throws -> CalendarWriteReceipt
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

    public func createEvent(calendarID: CalendarID, title: String, start: Date, end: Date, approved: Bool, runID: String?, sessionID: String?) async throws -> CalendarWriteReceipt {
        guard approved else { throw AgentToolError.permissionDenied("Calendar write approval required") }
        let event = CalendarEvent(
            id: CalendarEventID(rawValue: "event-\(UUID().uuidString)"),
            calendarID: calendarID,
            title: title,
            start: CalendarEventDateTime(date: start),
            end: CalendarEventDateTime(date: end)
        )
        events.append(event)
        return CalendarWriteReceipt(mutationKind: .createEvent, eventID: event.id, approved: true, summary: "Created approved calendar event \(event.id.rawValue)")
    }
}

public struct CalendarReadTool: AgentTool {
    public let runtime: any AgentCalendarRuntime
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

    public init(runtime: any AgentCalendarRuntime) { self.runtime = runtime }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let operation = arguments.string("operation") ?? "list_events"
        switch operation {
        case "list_calendars":
            let calendars = try await runtime.listCalendars(runID: context.runID, sessionID: context.sessionID)
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Listed \(calendars.count) calendars", contentJSON: try MailJSON.encode(calendars))
        case "list_events", "get_agenda":
            let events = try await runtime.listEvents(calendarID: arguments.string("calendarID").map(CalendarID.init(rawValue:)), runID: context.runID, sessionID: context.sessionID)
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Listed \(events.count) calendar events", contentJSON: try MailJSON.encode(events))
        case "get_event":
            guard let eventID = arguments.string("eventID") else { throw AgentToolError.invalidArguments("eventID is required") }
            let event = try await runtime.getEvent(id: CalendarEventID(rawValue: eventID), runID: context.runID, sessionID: context.sessionID)
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: event == nil ? "Calendar event not found" : "Loaded calendar event", contentJSON: try MailJSON.encode(event))
        case "get_free_busy":
            let events = try await runtime.listEvents(calendarID: arguments.string("calendarID").map(CalendarID.init(rawValue:)), runID: context.runID, sessionID: context.sessionID)
            let blocks = events.map { CalendarFreeBusyBlock(calendarID: $0.calendarID, start: $0.start.date, end: $0.end.date) }
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Computed \(blocks.count) free/busy blocks", contentJSON: try MailJSON.encode(blocks))
        default:
            throw AgentToolError.invalidArguments("Unsupported calendar_read operation: \(operation)")
        }
    }
}

public struct CalendarWriteTool: AgentTool {
    public let runtime: any AgentCalendarRuntime
    public var name: String { "calendar_write" }
    public var description: String { "Write Connor-owned calendar data using operations: create_event, update_event, delete_event, respond_to_invite. MVP supports create_event." }
    public var permission: AgentPermissionCapability { .mutateCalendar }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "operation": .string(description: "create_event | update_event | delete_event | respond_to_invite"),
            "calendarID": .string(description: "Calendar ID"),
            "title": .string(description: "Event title"),
            "start": .string(description: "ISO-8601 start timestamp"),
            "end": .string(description: "ISO-8601 end timestamp"),
            "approved": .boolean(description: "Explicit user approval")
        ], required: ["operation", "approved"])
    }

    public init(runtime: any AgentCalendarRuntime) { self.runtime = runtime }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let operation = arguments.string("operation") ?? ""
        guard operation == "create_event" else { throw AgentToolError.invalidArguments("MVP calendar_write supports create_event") }
        guard let calendarID = arguments.string("calendarID"), let title = arguments.string("title"), let startString = arguments.string("start"), let endString = arguments.string("end") else {
            throw AgentToolError.invalidArguments("calendarID, title, start, and end are required")
        }
        let formatter = ISO8601DateFormatter()
        guard let start = formatter.date(from: startString), let end = formatter.date(from: endString) else {
            throw AgentToolError.invalidArguments("start and end must be ISO-8601 timestamps")
        }
        let receipt = try await runtime.createEvent(calendarID: CalendarID(rawValue: calendarID), title: title, start: start, end: end, approved: arguments.bool("approved") ?? false, runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: receipt.summary, contentJSON: try MailJSON.encode(receipt))
    }
}

public extension AgentToolRegistry {
    mutating func registerNativeCalendarTools(runtime: any AgentCalendarRuntime) {
        register(CalendarReadTool(runtime: runtime))
        register(CalendarWriteTool(runtime: runtime))
    }
}
