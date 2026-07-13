import Foundation
import ConnorGraphCore

struct NoteImportActivitySummary: Equatable, Sendable {
    enum PresentationState: Equatable, Sendable {
        case running
        case paused
        case cancelling
    }

    let visibleJobCount: Int
    let runningJobCount: Int
    let pausedJobCount: Int
    let scanningJobCount: Int
    let cancellingJobCount: Int
    let processedCount: Int
    let totalCount: Int
    let hasUnknownProgress: Bool

    var isVisible: Bool { visibleJobCount > 0 }

    var progressFraction: Double? {
        guard totalCount > 0 else { return nil }
        return min(max(Double(processedCount) / Double(totalCount), 0), 1)
    }

    var presentationState: PresentationState {
        if cancellingJobCount > 0 { return .cancelling }
        if runningJobCount == 0, pausedJobCount > 0 { return .paused }
        return .running
    }

    init(jobs: [NoteImportJobRecord]) {
        let visibleJobs = jobs.filter(Self.isVisible)
        let pausedJobs = visibleJobs.filter(Self.isPaused)
        let knownJobs = visibleJobs.filter { $0.discoveredCount > 0 }

        visibleJobCount = visibleJobs.count
        pausedJobCount = pausedJobs.count
        runningJobCount = visibleJobs.count - pausedJobs.count
        scanningJobCount = visibleJobs.filter { $0.status == .scanning }.count
        cancellingJobCount = visibleJobs.filter { $0.status == .cancelling || $0.cancelRequestedAt != nil }.count
        processedCount = knownJobs.reduce(into: 0) { result, job in
            let processed = max(0, job.importedCount) + max(0, job.duplicateCount) + max(0, job.failedCount)
            result += min(processed, max(0, job.discoveredCount))
        }
        totalCount = knownJobs.reduce(0) { $0 + max(0, $1.discoveredCount) }
        hasUnknownProgress = visibleJobs.contains { $0.discoveredCount <= 0 }
    }

    static func isVisible(_ job: NoteImportJobRecord) -> Bool {
        !job.status.isTerminal
    }

    static func isPaused(_ job: NoteImportJobRecord) -> Bool {
        job.status == .paused || job.pauseRequestedAt != nil
    }

    static func processedCount(for job: NoteImportJobRecord) -> Int {
        min(
            max(0, job.importedCount) + max(0, job.duplicateCount) + max(0, job.failedCount),
            max(0, job.discoveredCount)
        )
    }
}
