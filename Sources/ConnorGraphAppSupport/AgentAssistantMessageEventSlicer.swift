import Foundation

public struct AgentAssistantMessageEventSlicer: Sendable {
    public init() {}

    public func events(
        forAssistantMessageID messageID: String?,
        from events: [AgentEventPresentation]
    ) -> [AgentEventPresentation] {
        guard let messageID else { return events }
        let boundaries = events.indices.filter { events[$0].assistantMessageID != nil }
        guard !boundaries.isEmpty else { return events }

        if let boundaryPosition = boundaries.firstIndex(where: { events[$0].assistantMessageID == messageID }) {
            let end = boundaries[boundaryPosition]
            let start = boundaryPosition == boundaries.startIndex ? events.startIndex : events.index(after: boundaries[boundaries.index(before: boundaryPosition)])
            return Array(events[start..<end])
        }

        guard let lastBoundary = boundaries.last else { return events }
        return Array(events[events.index(after: lastBoundary)..<events.endIndex])
    }
}
