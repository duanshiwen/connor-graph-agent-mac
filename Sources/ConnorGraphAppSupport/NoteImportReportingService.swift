import Foundation
import ConnorGraphCore

public struct NoteImportReport: Codable, Sendable, Equatable {
    public var job: NoteImportJobRecord
    public var statusCounts: [String: Int]
    public var failures: [NoteImportReportFailure]
    public var generatedAt: Date
}
public struct NoteImportReportFailure: Codable, Sendable, Equatable { public var itemID: String; public var relativePath: String?; public var code: NoteImportErrorCode?; public var message: String? }
public enum NoteImportRecoveryAction: String, Sendable, CaseIterable { case pause, resume, cancelRemaining, retryFailed, reauthorizeSource, reviewEncoding, openSession }

public struct NoteImportReportingService: Sendable {
    public init() {}
    public func report(job: NoteImportJobRecord, items: [NoteImportItemRecord], now: Date = Date()) -> NoteImportReport {
        let counts = Dictionary(grouping: items, by: { $0.status.rawValue }).mapValues(\.count)
        let failures: [NoteImportReportFailure] = items.filter { $0.errorCode != nil || [NoteImportItemStatus.parseFailed, .sessionFailed, .attachmentFailed, .llmFailed].contains($0.status) }.map { NoteImportReportFailure(itemID: $0.id, relativePath: $0.relativePath, code: $0.errorCode, message: $0.errorMessage) }
        return .init(job: job, statusCounts: counts, failures: failures, generatedAt: now)
    }
    public func markdown(_ report: NoteImportReport) -> String {
        var lines = ["# 笔记导入报告", "", "- Job: `\(report.job.id)`", "- 状态: `\(report.job.status.rawValue)`", "- 发现: \(report.job.discoveredCount)", "- 已导入: \(report.job.importedCount)", "- 失败: \(report.job.failedCount)", "", "## 状态统计"]
        lines += report.statusCounts.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value)" }
        if !report.failures.isEmpty { lines += ["", "## 失败与需处理项目"]; lines += report.failures.map { "- `\($0.itemID)` \($0.relativePath ?? "") [\($0.code?.rawValue ?? "unknown")]: \($0.message ?? "")" } }
        return lines.joined(separator: "\n") + "\n"
    }
    public func json(_ report: NoteImportReport) throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; return try encoder.encode(report) }
    public func actions(job: NoteImportJobRecord, items: [NoteImportItemRecord]) -> Set<NoteImportRecoveryAction> { var actions: Set<NoteImportRecoveryAction> = []; if [.importing, .processing, .scanning].contains(job.status) { actions.formUnion([.pause, .cancelRemaining]) }; if job.status == .paused || job.pauseRequestedAt != nil { actions.insert(.resume) }; if items.contains(where: { [.parseFailed, .sessionFailed, .attachmentFailed, .llmFailed].contains($0.status) }) { actions.insert(.retryFailed) }; if items.contains(where: { $0.status == .needsEncodingReview }) { actions.insert(.reviewEncoding) }; if items.contains(where: { $0.sessionID != nil }) { actions.insert(.openSession) }; if job.errorCode == .sourceAccessDenied { actions.insert(.reauthorizeSource) }; return actions }
}
