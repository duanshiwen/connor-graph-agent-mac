import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Note import reporting")
struct NoteImportReportingServiceTests {
    @Test("Produces redacted machine and user reports")
    func reports() throws { let job = NoteImportJobRecord(id: "job", sourceID: "source", status: .completedWithIssues, discoveredCount: 2, importedCount: 1, failedCount: 1); let items = [NoteImportItemRecord(id: "ok", jobID: "job", sourceID: "source", sourceIdentity: "a", relativePath: "a.md", title: "A", status: .completed, sessionID: "session", rawByteHash: "a", normalizedTextHash: "a", metadata: ["content": "SECRET BODY"]), NoteImportItemRecord(id: "bad", jobID: "job", sourceID: "source", sourceIdentity: "b", relativePath: "b.md", title: "B", status: .llmFailed, rawByteHash: "b", normalizedTextHash: "b", errorCode: .llmRateLimited, errorMessage: "429")]; let service = NoteImportReportingService(); let report = service.report(job: job, items: items); let markdown = service.markdown(report); let json = String(decoding: try service.json(report), as: UTF8.self); #expect(markdown.contains("llm_rate_limited")); #expect(!markdown.contains("SECRET BODY")); #expect(!json.contains("SECRET BODY")); #expect(report.statusCounts["completed"] == 1) }
    @Test("Offers actions matching persisted state")
    func actions() { var job = NoteImportJobRecord(id: "job", sourceID: "source", status: .processing); job.pauseRequestedAt = Date(); let items = [NoteImportItemRecord(jobID: "job", sourceID: "source", sourceIdentity: "a", title: "A", status: .needsEncodingReview, sessionID: "s", rawByteHash: "a", normalizedTextHash: "a"), NoteImportItemRecord(jobID: "job", sourceID: "source", sourceIdentity: "b", title: "B", status: .attachmentFailed, rawByteHash: "b", normalizedTextHash: "b")]; let actions = NoteImportReportingService().actions(job: job, items: items); #expect(actions.isSuperset(of: [.pause, .resume, .cancelRemaining, .retryFailed, .reviewEncoding, .openSession])) }
}
