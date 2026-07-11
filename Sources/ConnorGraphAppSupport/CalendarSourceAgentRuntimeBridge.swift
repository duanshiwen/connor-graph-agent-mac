import Foundation
import ConnorGraphCore
import ConnorGraphAgent

public struct CalendarSourceAgentRuntimeBridge: AgentCalendarRuntime {
    private let store: FileBackedCalendarSourceRuntimeStore
    private let mutationService: CalendarMutationService?

    public init(store: FileBackedCalendarSourceRuntimeStore, mutationService: CalendarMutationService? = nil) {
        self.store = store
        self.mutationService = mutationService
    }

    public func listCalendars(runID: String?, sessionID: String?) async throws -> [CalendarCollection] {
        try await store.loadSnapshot().collections
    }

    public func listEvents(calendarID: CalendarID?, runID: String?, sessionID: String?) async throws -> [CalendarEvent] {
        let events = try await store.loadSnapshot().events
        let filtered = calendarID.map { id in events.filter { $0.calendarID == id } } ?? events
        return filtered.sorted { $0.start.date < $1.start.date }
    }

    public func searchEvents(query: String, startDate: Date?, endDate: Date?, timePreset: String?, timeFilterMode: String?, timeSort: String?, limit: Int, runID: String?, sessionID: String?) async throws -> [CalendarEvent] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let events = try await store.loadSnapshot().events
        let filtered = events.filter { event in
            if let startDate, event.end.date < startDate { return false }
            if let endDate, event.start.date > endDate { return false }
            guard !normalized.isEmpty else { return true }
            return event.title.lowercased().contains(normalized)
                || (event.notes?.lowercased().contains(normalized) ?? false)
                || (event.location?.lowercased().contains(normalized) ?? false)
                || event.attendees.contains { ($0.name?.lowercased().contains(normalized) ?? false) || ($0.email?.lowercased().contains(normalized) ?? false) }
        }
        let ascending = timeSort == nil || timeSort == "timeAscThenRelevance" || timeSort == "relevanceThenTimeAsc"
        let sorted = filtered.sorted { ascending ? $0.start.date < $1.start.date : $0.start.date > $1.start.date }
        return Array(sorted.prefix(max(0, limit)))
    }

    public func getEvent(id: CalendarEventID, runID: String?, sessionID: String?) async throws -> CalendarEvent? {
        try await store.loadSnapshot().events.first { $0.id == id }
    }

    public func mutate(_ request: CalendarMutationRequest) async throws -> CalendarMutationResult {
        guard let mutationService else { throw AgentToolError.permissionDenied("日历真实写入适配器尚未连接。") }
        return try await mutationService.mutate(request)
    }
}
