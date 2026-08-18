import Foundation
import ConnorGraphCore

private enum CalendarToolJSON {
    private static func encodedObject<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }

    private static func string(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func encodeCalendars(_ calendars: [CalendarCollection]) throws -> String {
        var rows = (try encodedObject(calendars) as? [[String: Any]]) ?? []
        for index in rows.indices {
            if let id = rows[index]["id"] { rows[index]["calendarID"] = id }
        }
        return try string(rows)
    }

    static func encodeEvents(_ events: [CalendarEvent]) throws -> String {
        var rows = (try encodedObject(events) as? [[String: Any]]) ?? []
        for index in rows.indices {
            if let id = rows[index]["id"] { rows[index]["eventID"] = id }
        }
        return try string(rows)
    }

    static func encodeEvent(_ event: CalendarEvent) throws -> String {
        var object = (try encodedObject(event) as? [String: Any]) ?? [:]
        if let id = object["id"] { object["eventID"] = id }
        if let metadata = object["sourceMetadata"] as? [String: Any], let etag = metadata["etag"] {
            object["expectedVersion"] = etag
        }
        return try string(object)
    }
}

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
    public var description: String { "Search Connor-owned calendar events as candidate results. For an absolute range, pass startDate and endDate as timezone-qualified RFC 3339 timestamps; the canonical form is 2026-07-29T05:03:12+08:00, and fractional seconds are also accepted. Alternatively pass timePreset without dates. Empty query performs a time-only search. Common legacy aliases and snake_case parameters are normalized. Use calendar_read with operation get_event for selected event detail reads that should become Memory OS evidence." }
    public var permission: AgentPermissionCapability { .readCalendar }
    public var inputSchema: AgentToolInputSchema {
        .closedObject(properties: [
            "query": .string(description: "Search query; leave empty to search by time range only"),
            "startDate": .string(description: "Optional inclusive RFC 3339/ISO-8601 timestamp with timezone; fractional seconds are accepted. Prefer an exact timestamp derived from get_current_time.iso8601"),
            "endDate": .string(description: "Optional exclusive RFC 3339/ISO-8601 timestamp with timezone; fractional seconds are accepted. Derive it from the same get_current_time result as startDate"),
            "timePreset": .stringEnumeration(values: NativeSearchTimePreset.allCases.map(\.rawValue), description: "Optional relative time range."),
            "timeFilterMode": .stringEnumeration(values: NativeSearchTemporalFilterMode.allCases.map(\.rawValue), description: "Optional temporal matching mode."),
            "timeSort": .stringEnumeration(values: NativeSearchTemporalSort.allCases.map(\.rawValue), description: "Optional temporal result ordering."),
            "limit": .integer(description: "Maximum event details to return")
        ], required: [])
    }

    public init(runtime: any AgentCalendarRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        self.runtime = runtime
        self.recorder = recorder
    }

    public var inputExamples: [[String: SendableJSONValue]] {
        [[
            "query": .string(""),
            "startDate": .string("2026-07-29T05:03:12+08:00"),
            "endDate": .string("2026-07-31T05:03:12+08:00"),
            "timeFilterMode": .string("intervalOverlapsRange"),
            "timeSort": .string("timeAscThenRelevance"),
            "limit": .int(50)
        ]]
    }

    public func normalizeLegacyArguments(_ arguments: AgentToolArguments) -> AgentToolArguments {
        arguments.normalizingAliases([
            "query": ["q", "keyword", "searchText", "searchQuery"],
            "startDate": ["start", "startTime", "from", "fromDate"],
            "endDate": ["end", "endTime", "to", "toDate"],
            "timePreset": ["preset"],
            "timeFilterMode": ["filterMode"],
            "timeSort": ["sort", "sortOrder"],
            "limit": ["maxResults", "maxItems", "pageSize"]
        ])
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let startDate = try arguments.iso8601Date("startDate")
        let endDate = try arguments.iso8601Date("endDate")
        if let startDate, let endDate, startDate >= endDate {
            throw AgentToolError.invalidArguments("startDate must be earlier than endDate")
        }
        let events = try await runtime.searchEvents(
            query: arguments.string("query") ?? "",
            startDate: startDate,
            endDate: endDate,
            timePreset: arguments.string("timePreset"),
            timeFilterMode: arguments.string("timeFilterMode"),
            timeSort: arguments.string("timeSort"),
            limit: NativeSearchLimitPolicy.clampSearchLimit(arguments.int("limit") ?? NativeSearchLimitPolicy.defaultSearchLimit),
            runID: context.runID,
            sessionID: context.sessionID
        )
        await recorder?.record(events.map { NativeSourceReference.calendarEvent($0, query: arguments.string("query"), strength: .summaryCandidate, toolName: name, context: context) })
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: CalendarEventCandidateTextRenderer.render(events, verb: "Found"), contentJSON: try CalendarToolJSON.encodeEvents(events))
    }
}

/// Returns upcoming events across every calendar within a near-term look-ahead
/// window in a single call. It resolves the window from the current time on the
/// server and loads all calendars at once, so the model never has to call
/// get_current_time or list_calendars first, nor iterate calendars one by one.
/// The read-only `.readCalendar` capability keeps it safe to run in parallel
/// with other read tools.
public struct CalendarUpcomingEventsTool: AgentTool {
    public let runtime: any AgentCalendarRuntime
    public let recorder: (any NativeSourceReferenceRecording)?
    public static let defaultLookAheadDays = 2
    public static let maximumLookAheadDays = 31
    public var name: String { "calendar_upcoming_events" }
    public var description: String { "List upcoming events across ALL of Connor's calendars within a near-term look-ahead window, sorted by start time. This is the fastest way to see what is coming up: it needs no prior get_current_time or list_calendars call, computes the window from the current time on the server, and never requires iterating calendars yourself. The window defaults to the next \(Self.defaultLookAheadDays) days; pass days to widen or narrow it (1–\(Self.maximumLookAheadDays)). Use calendar_search_events when you need a keyword or an explicit absolute range, and calendar_read with operation get_event for a detailed evidence read." }
    public var permission: AgentPermissionCapability { .readCalendar }
    public var inputSchema: AgentToolInputSchema {
        .closedObject(properties: [
            "days": .integer(description: "Optional look-ahead window in days from now (default \(Self.defaultLookAheadDays), max \(Self.maximumLookAheadDays)). Events overlapping this window in any calendar are returned."),
            "limit": .integer(description: "Maximum events to return")
        ], required: [])
    }

    public init(runtime: any AgentCalendarRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        self.runtime = runtime
        self.recorder = recorder
    }

    public var inputExamples: [[String: SendableJSONValue]] {
        [[:], ["days": .int(3)]]
    }

    public func normalizeLegacyArguments(_ arguments: AgentToolArguments) -> AgentToolArguments {
        arguments.normalizingAliases([
            "days": ["lookAheadDays", "windowDays", "horizonDays", "rangeDays"],
            "limit": ["maxResults", "maxItems", "pageSize"]
        ])
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let requestedDays = arguments.int("days") ?? Self.defaultLookAheadDays
        let days = min(max(1, requestedDays), Self.maximumLookAheadDays)
        let now = Date()
        let endDate = now.addingTimeInterval(TimeInterval(days) * 86_400)
        let events = try await runtime.searchEvents(
            query: "",
            startDate: now,
            endDate: endDate,
            timePreset: nil,
            timeFilterMode: NativeSearchTemporalFilterMode.intervalOverlapsRange.rawValue,
            timeSort: NativeSearchTemporalSort.timeAscThenRelevance.rawValue,
            limit: NativeSearchLimitPolicy.clampSearchLimit(arguments.int("limit") ?? NativeSearchLimitPolicy.defaultSearchLimit),
            runID: context.runID,
            sessionID: context.sessionID
        )
        await recorder?.record(events.map { NativeSourceReference.calendarEvent($0, query: nil, strength: .summaryCandidate, toolName: name, context: context) })
        let window = "next \(days) day\(days == 1 ? "" : "s") across all calendars"
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: CalendarEventCandidateTextRenderer.render(events, verb: "Found upcoming events (\(window)):"), contentJSON: try CalendarToolJSON.encodeEvents(events))
    }
}

public struct CalendarDetailReadEvidence: Sendable, Equatable {
    public var runID: String
    public var sessionID: String
    public var eventID: String
    public var calendarID: String
    public var expectedVersion: String
    public var readAt: Date

    public init(runID: String, sessionID: String, eventID: String, calendarID: String, expectedVersion: String, readAt: Date = Date()) {
        self.runID = runID
        self.sessionID = sessionID
        self.eventID = eventID
        self.calendarID = calendarID
        self.expectedVersion = expectedVersion
        self.readAt = readAt
    }
}

public actor CalendarDetailReadEvidenceRegistry {
    private var entries: [String: CalendarDetailReadEvidence] = [:]
    private let maximumEntries: Int

    public init(maximumEntries: Int = 256) { self.maximumEntries = max(1, maximumEntries) }

    public func record(_ evidence: CalendarDetailReadEvidence) {
        entries[key(runID: evidence.runID, sessionID: evidence.sessionID, eventID: evidence.eventID)] = evidence
        if entries.count > maximumEntries, let oldest = entries.min(by: { $0.value.readAt < $1.value.readAt })?.key { entries.removeValue(forKey: oldest) }
    }

    public func matches(runID: String, sessionID: String, eventID: String, expectedVersion: String) -> Bool {
        guard let evidence = entries[key(runID: runID, sessionID: sessionID, eventID: eventID)] else { return false }
        return evidence.expectedVersion == expectedVersion
    }

    public func evidence(runID: String, sessionID: String, eventID: String) -> CalendarDetailReadEvidence? {
        entries[key(runID: runID, sessionID: sessionID, eventID: eventID)]
    }

    public func debugDescription() -> String {
        entries.values.map { "\($0.runID)|\($0.sessionID)|\($0.eventID)|\($0.calendarID)|\($0.expectedVersion)" }.joined(separator: "\n")
    }

    private func key(runID: String, sessionID: String, eventID: String) -> String { "\(runID)\u{1F}\(sessionID)\u{1F}\(eventID)" }
}

public struct CalendarReadTool: AgentTool {
    public let runtime: any AgentCalendarRuntime
    public let recorder: (any NativeSourceReferenceRecording)?
    public let evidenceRegistry: CalendarDetailReadEvidenceRegistry?
    public var name: String { "calendar_read" }
    public var description: String { "Read Connor-owned calendar data using operations: list_calendars, list_events, get_event, get_agenda, get_free_busy." }
    public var permission: AgentPermissionCapability { .readCalendar }
    public var inputSchema: AgentToolInputSchema {
        .closedObject(properties: [
            "operation": .stringEnumeration(values: ["list_calendars", "list_events", "get_event", "get_agenda", "get_free_busy"], description: "Calendar read operation"),
            "calendarID": .string(description: "Exact calendarID returned by list_calendars; copy the field without renaming it. Optional for list_events, get_agenda, and get_free_busy"),
            "eventID": .string(description: "Exact eventID returned by calendar_search_events or list_events; copy the field without renaming it. Required for get_event")
        ], required: ["operation"])
    }

    public init(runtime: any AgentCalendarRuntime, recorder: (any NativeSourceReferenceRecording)? = nil, evidenceRegistry: CalendarDetailReadEvidenceRegistry? = nil) {
        self.runtime = runtime
        self.recorder = recorder
        self.evidenceRegistry = evidenceRegistry
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let operation = arguments.string("operation") else {
            throw AgentToolError.invalidArguments("Missing required calendar_read argument: operation. Use list_calendars, list_events, get_event, get_agenda, or get_free_busy.")
        }
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
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: summary, contentJSON: try CalendarToolJSON.encodeCalendars(calendars))
        case "list_events", "get_agenda":
            let events = try await runtime.listEvents(calendarID: arguments.string("calendarID").map(CalendarID.init(rawValue:)), runID: context.runID, sessionID: context.sessionID)
            await recorder?.record(events.map { NativeSourceReference.calendarEvent($0, query: nil, strength: .summaryCandidate, toolName: name, context: context) })
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: CalendarEventCandidateTextRenderer.render(events, verb: "Listed"), contentJSON: try CalendarToolJSON.encodeEvents(events))
        case "get_event":
            guard let eventID = arguments.string("eventID") else { throw AgentToolError.invalidArguments("eventID is required for calendar_read get_event. Copy an exact eventID returned by calendar_search_events or list_events.") }
            let event = try await runtime.getEvent(id: CalendarEventID(rawValue: eventID), runID: context.runID, sessionID: context.sessionID)
            if let event {
                await recorder?.record([NativeSourceReference.calendarEvent(event, query: nil, strength: .detailRead, toolName: name, context: context)])
                if mutationEligibility(event) == "eligible", let version = event.sourceMetadata?.etag, !version.isEmpty {
                    await evidenceRegistry?.record(.init(runID: context.runID, sessionID: context.sessionID, eventID: event.id.rawValue, calendarID: event.calendarID.rawValue, expectedVersion: version))
                }
                return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: CalendarEventDetailTextRenderer.render(event), contentJSON: try CalendarToolJSON.encodeEvent(event))
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
    public let evidenceRegistry: CalendarDetailReadEvidenceRegistry?
    public var name: String { "calendar_write" }
    public var description: String { "Create, update, or delete calendar events, including recurring events, through the current session permission policy. Every call must include operation, even when the other fields make it seem obvious; for creation use {\"operation\":\"create_event\",\"calendarID\":\"<exact writable ID>\",\"title\":\"<title>\",\"start\":\"2026-07-29T05:03:12+08:00\",\"end\":\"2026-07-29T06:03:12+08:00\",\"isAllDay\":false}. start and end require timezone-qualified RFC 3339 timestamps; fractional seconds are accepted. For a recurring event, pass recurrence as an object like {\"frequency\":\"weekly\",\"interval\":1,\"count\":10} or {\"frequency\":\"monthly\",\"until\":\"2026-12-31T16:00:00Z\"}; frequency is daily/weekly/monthly/yearly, interval defaults to 1, until and count are mutually exclusive. calendarID is only for create_event; first call calendar_read list_calendars and copy an exact writable ID, because 'default', display names, and example IDs are invalid. eventID and expectedVersion are only for update_event and delete_event; copy both exactly from a successful calendar_read get_event and never overwrite a conflict. For update_event/delete_event on a recurring series, scope defaults to entireSeries; use scope thisEvent or futureEvents with instanceStart (an occurrence's start timestamp from calendar_read) to change only one instance or this and later instances where the source supports it." }
    public var permission: AgentPermissionCapability { .mutateCalendar }
    public var inputExamples: [[String: SendableJSONValue]] {
        [
            [
                "operation": .string("create_event"),
                "calendarID": .string("exact-calendar-id-from-list-calendars"),
                "title": .string("Project review"),
                "start": .string("2026-07-12T02:00:00Z"),
                "end": .string("2026-07-12T03:00:00Z"),
                "isAllDay": .bool(false),
                "recurrence": .object(["frequency": .string("weekly"), "interval": .int(1), "count": .int(10)])
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
            "calendarID": .string(description: "Exact writable calendarID returned by calendar_read list_calendars; copy the field without renaming it. Required for create_event"),
            "eventID": .string(description: "Exact eventID returned by calendar_read get_event; copy the field without renaming it. Required for update_event and delete_event"),
            "expectedVersion": .string(description: "Exact expectedVersion returned by the latest calendar_read get_event; copy the field without renaming it. Required for update_event and delete_event"),
            "title": .string(description: "Event title"),
            "start": .string(description: "RFC 3339/ISO-8601 start timestamp with timezone; fractional seconds are accepted"),
            "end": .string(description: "RFC 3339/ISO-8601 end timestamp with timezone; fractional seconds are accepted"),
            "isAllDay": .boolean(description: "Whether this is an all-day event"),
            "location": .string(description: "Event location"),
            "url": .string(description: "Event URL"),
            "notes": .string(description: "Event notes"),
            "recurrence": .object(properties: [
                "frequency": .stringEnumeration(values: ["daily", "weekly", "monthly", "yearly"], description: "Repeat frequency; required"),
                "interval": .integer(description: "Repeat every N periods; default 1"),
                "until": .string(description: "Optional end date-time (RFC 3339); mutually exclusive with count"),
                "count": .integer(description: "Optional total occurrence count; mutually exclusive with until")
            ], required: []),
            "scope": .stringEnumeration(values: ["thisEvent", "futureEvents", "entireSeries"], description: "update/delete scope; entireSeries is default. thisEvent/futureEvents require instanceStart and are honored by EventKit-backed calendars"),
            "instanceStart": .string(description: "Start timestamp of the specific occurrence to target when scope is thisEvent or futureEvents; copy from calendar_read"),
            "clearLocation": .boolean(description: "Clear the existing location on update"),
            "clearURL": .boolean(description: "Clear the existing URL on update"),
            "clearNotes": .boolean(description: "Clear the existing notes on update"),
            "clearRecurrence": .boolean(description: "Clear recurrence on update, turning a recurring series into a single event")
        ], required: ["operation"])
    }

    public init(runtime: any AgentCalendarRuntime, evidenceRegistry: CalendarDetailReadEvidenceRegistry? = nil) {
        self.runtime = runtime
        self.evidenceRegistry = evidenceRegistry
    }

    public func normalizeLegacyArguments(_ arguments: AgentToolArguments) -> AgentToolArguments {
        arguments.normalizingAliases([
            "start": ["startDate", "startTime"],
            "end": ["endDate", "endTime"]
        ])
    }

    public func preflight(call: AgentToolCall, context: AgentToolExecutionContext) async throws {
        let arguments = try AgentToolArguments(json: call.argumentsJSON)
        guard let operation = arguments.string("operation") else {
            throw AgentToolError.invalidArguments("Missing required calendar_write argument: operation. Use create_event, update_event, or delete_event.")
        }
        guard operation == "update_event" || operation == "delete_event" else { return }
        guard let eventID = arguments.string("eventID"), let expectedVersion = arguments.string("expectedVersion") else { return }
        guard let evidenceRegistry,
              let evidence = await evidenceRegistry.evidence(runID: context.runID, sessionID: context.sessionID, eventID: eventID) else {
            throw AgentToolError.invalidArguments("Calendar \(operation) requires a successful calendar_read get_event in this run and session. Search or list events, copy an exact eventID, then read it before requesting a mutation.")
        }
        guard evidence.expectedVersion == expectedVersion else {
            throw AgentToolError.invalidArguments("expectedVersion does not match the latest successful detail read for eventID '\(eventID)'. Copy eventID and expectedVersion exactly from calendar_read get_event.")
        }
    }

    public func approvalPayloadJSON(for call: AgentToolCall, context: AgentToolExecutionContext) async -> String {
        guard let arguments = try? AgentToolArguments(json: call.argumentsJSON),
              let eventID = arguments.string("eventID"),
              let evidence = await evidenceRegistry?.evidence(runID: context.runID, sessionID: context.sessionID, eventID: eventID),
              let event = try? await runtime.getEvent(id: .init(rawValue: eventID), runID: context.runID, sessionID: context.sessionID)
        else { return call.argumentsJSON }
        var payload = arguments.values
        payload["verifiedEventTitle"] = .string(event.title)
        payload["verifiedCalendarID"] = .string(evidence.calendarID)
        guard let data = try? JSONSerialization.data(withJSONObject: payload.mapValues(\.jsonCompatibleObject), options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) else { return call.argumentsJSON }
        return text
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard context.approvedCapabilities.contains(.mutateCalendar) else { throw AgentToolError.permissionDenied("Calendar write requires an authorized mutateCalendar capability") }
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
            guard let start = AgentToolTimestampParser.parse(startText) else { throw AgentToolError.invalidArguments("Invalid ISO-8601 start timestamp; RFC 3339 with timezone is required: \(startText)") }
            guard let end = AgentToolTimestampParser.parse(endText) else { throw AgentToolError.invalidArguments("Invalid ISO-8601 end timestamp; RFC 3339 with timezone is required: \(endText)") }
            request = CalendarMutationRequest(operation: .create, draft: CalendarEventDraft(calendarID: CalendarID(rawValue: calendarID), title: title, start: CalendarEventDateTime(date: start), end: CalendarEventDateTime(date: end), isAllDay: arguments.bool("isAllDay") ?? false, location: arguments.string("location"), url: arguments.string("url").flatMap(URL.init(string:)), notes: arguments.string("notes"), recurrence: recurrenceArgument(arguments)), runID: context.runID, sessionID: context.sessionID)
        case "update_event":
            let missingKeys = ["eventID", "expectedVersion"].filter { arguments.string($0) == nil }
            guard missingKeys.isEmpty else { throw AgentToolError.invalidArguments("Missing required update_event arguments: \(missingKeys.joined(separator: ", ")). Required fields are eventID, expectedVersion.") }
            let eventID = arguments.string("eventID")!
            let expectedVersion = arguments.string("expectedVersion")!
            if mutationScope(arguments) != .entireSeries && arguments.string("instanceStart") == nil {
                throw AgentToolError.invalidArguments("scope thisEvent/futureEvents requires instanceStart: copy the exact occurrence start from calendar_read get_event. Use entireSeries (default) to modify the whole series.")
            }
            if let startText = arguments.string("start"), AgentToolTimestampParser.parse(startText) == nil { throw AgentToolError.invalidArguments("Invalid ISO-8601 start timestamp; RFC 3339 with timezone is required: \(startText)") }
            if let endText = arguments.string("end"), AgentToolTimestampParser.parse(endText) == nil { throw AgentToolError.invalidArguments("Invalid ISO-8601 end timestamp; RFC 3339 with timezone is required: \(endText)") }
            request = CalendarMutationRequest(operation: .update, eventID: CalendarEventID(rawValue: eventID), expectedVersion: CalendarMutationVersion(value: expectedVersion), patch: CalendarEventPatch(title: arguments.string("title").map(CalendarPatchValue.set) ?? .unchanged, start: datePatch("start", arguments: arguments), end: datePatch("end", arguments: arguments), isAllDay: arguments.bool("isAllDay").map(CalendarPatchValue.set) ?? .unchanged, location: optionalPatch(value: arguments.string("location"), clear: arguments.bool("clearLocation") == true), url: optionalPatch(value: arguments.string("url").flatMap(URL.init(string:)), clear: arguments.bool("clearURL") == true), notes: optionalPatch(value: arguments.string("notes"), clear: arguments.bool("clearNotes") == true), recurrence: recurrencePatch(arguments)), scope: mutationScope(arguments), occurrenceDate: instanceStartArgument(arguments), runID: context.runID, sessionID: context.sessionID)
        case "delete_event":
            let missingKeys = ["eventID", "expectedVersion"].filter { arguments.string($0) == nil }
            guard missingKeys.isEmpty else { throw AgentToolError.invalidArguments("Missing required delete_event arguments: \(missingKeys.joined(separator: ", ")). Required fields are eventID, expectedVersion.") }
            if mutationScope(arguments) != .entireSeries && arguments.string("instanceStart") == nil {
                throw AgentToolError.invalidArguments("scope thisEvent/futureEvents requires instanceStart: copy the exact occurrence start from calendar_read get_event. Use entireSeries (default) to delete the whole series.")
            }
            request = CalendarMutationRequest(operation: .delete, eventID: CalendarEventID(rawValue: arguments.string("eventID")!), expectedVersion: CalendarMutationVersion(value: arguments.string("expectedVersion")!), scope: mutationScope(arguments), occurrenceDate: instanceStartArgument(arguments), runID: context.runID, sessionID: context.sessionID)
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
            return .invalidArguments("This calendar source does not support recurring event mutation for the requested scope. No write was performed.")
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

    private func datePatch(_ key: String, arguments: AgentToolArguments) -> CalendarPatchValue<CalendarEventDateTime> {
        guard let text = arguments.string(key), let date = AgentToolTimestampParser.parse(text) else { return .unchanged }
        return .set(CalendarEventDateTime(date: date))
    }

    private func recurrenceArgument(_ arguments: AgentToolArguments) -> CalendarRecurrence? {
        recurrence(from: arguments.values["recurrence"])
    }

    private func recurrencePatch(_ arguments: AgentToolArguments) -> CalendarPatchValue<CalendarRecurrence> {
        if let recurrence = recurrenceArgument(arguments) { return .set(recurrence) }
        if arguments.bool("clearRecurrence") == true { return .clear }
        return .unchanged
    }

    private func mutationScope(_ arguments: AgentToolArguments) -> CalendarMutationScope {
        switch arguments.string("scope") {
        case "thisEvent": return .thisEvent
        case "futureEvents": return .futureEvents
        default: return .entireSeries
        }
    }

    private func instanceStartArgument(_ arguments: AgentToolArguments) -> Date? {
        guard let text = arguments.string("instanceStart") else { return nil }
        return AgentToolTimestampParser.parse(text)
    }

    private func recurrence(from value: SendableJSONValue?) -> CalendarRecurrence? {
        guard case .object(let values)? = value else { return nil }
        func string(_ key: String) -> String? { if case .string(let value)? = values[key] { return value }; return nil }
        func int(_ key: String) -> Int? { if case .int(let value)? = values[key] { return value }; return nil }
        guard let raw = string("frequency")?.lowercased(), let frequency = CalendarRecurrenceFrequency(rawValue: raw) else { return nil }
        return CalendarRecurrence(
            frequency: frequency,
            interval: int("interval") ?? 1,
            until: string("until").flatMap(AgentToolTimestampParser.parse),
            count: int("count")
        )
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
            "recurrence: \(event.recurrenceSummary?.ruleDescription ?? "none")",
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
    mutating func registerNativeCalendarTools(runtime: any AgentCalendarRuntime, recorder: (any NativeSourceReferenceRecording)? = nil, evidenceRegistry: CalendarDetailReadEvidenceRegistry = .init()) {
        register(CalendarSearchEventsTool(runtime: runtime, recorder: recorder))
        register(CalendarUpcomingEventsTool(runtime: runtime, recorder: recorder))
        register(CalendarReadTool(runtime: runtime, recorder: recorder, evidenceRegistry: evidenceRegistry))
        register(CalendarWriteTool(runtime: runtime, evidenceRegistry: evidenceRegistry))
    }
}
