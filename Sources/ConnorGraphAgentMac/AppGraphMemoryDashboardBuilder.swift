import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphAppSupport

struct AppGraphMemoryDashboardBuilder {
    func build(
        graphWriteCandidates: [GraphWriteCandidate],
        admissionHoldQueueItems: [AppGraphAdmissionHoldQueuePresentation],
        memoryChangeLogEntries: [AppGraphMemoryChangeLogPresentation]
    ) -> GraphMemoryDashboard {
        let pendingCandidates = graphWriteCandidates.filter { $0.status == .pendingReview || $0.status == .validationFailed }
        let memoryCards: [GraphMemoryProductCard] = admissionHoldQueueItems.map { item in
            GraphMemoryProductCard(
                id: item.id,
                kind: .admissionHold,
                title: item.title,
                detail: item.detail,
                severity: .needsReview,
                recommendedActions: item.recommendedActions.map(\.rawValue),
                createdAt: item.createdAt
            )
        } + pendingCandidates.map { candidate in
            GraphMemoryProductCard(
                id: candidate.id,
                kind: .writeCandidate,
                title: "\(candidate.kind.rawValue) · \(candidate.status.rawValue)",
                detail: candidate.rationale,
                severity: candidate.status == .validationFailed ? .error : .needsReview,
                sourceIDs: candidate.sourceEpisodeIDs,
                createdAt: candidate.createdAt
            )
        } + memoryChangeLogEntries.prefix(5).map { entry in
            GraphMemoryProductCard(
                id: entry.id,
                kind: .changeLog,
                title: entry.title,
                detail: entry.detail,
                severity: entry.action == .extractionCommitted ? .success : .info,
                createdAt: entry.createdAt
            )
        }
        return GraphMemoryDashboard(
            summary: GraphMemoryDashboardSummary(
                pendingCandidateCount: pendingCandidates.count,
                openHoldCount: admissionHoldQueueItems.count,
                recentChangeCount: memoryChangeLogEntries.count
            ),
            cards: memoryCards
        )
    }
}
