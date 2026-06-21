import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Native Source Search Evaluation Tests")
struct NativeSourceSearchEvaluationTests {
    @Test func mailEvaluationCoversSubjectSenderBodyChineseAndTime() async throws {
        let service = NativeSourceSearchService()
        let recent = Date(timeIntervalSince1970: 20_000)
        let old = Date(timeIntervalSince1970: 1_000)
        try await service.upsert([
            mail(id: "subject", title: "Project Phoenix decision", summary: "Decision summary", participants: ["alice@example.com"], body: "English body", sentAt: recent),
            mail(id: "sender", title: "Weekly update", summary: "From Bob", participants: ["bob@example.com"], body: "General update", sentAt: recent),
            mail(id: "chinese", title: "中文邮件", summary: "摘要", participants: ["chen@example.com"], body: "这封邮件讨论搜索性能优化和中文分词。", sentAt: recent),
            mail(id: "old", title: "Project Phoenix decision", summary: "Old summary", participants: ["alice@example.com"], body: "Old body", sentAt: old)
        ])

        let subjectResults = try await service.search(NativeSearchQuery(text: "project phoenix"))
        #expect(subjectResults.first?.id == "subject")

        let senderResults = try await service.search(NativeSearchQuery(text: "bob@example.com"))
        #expect(senderResults.first?.id == "sender")

        let chineseResults = try await service.search(NativeSearchQuery(text: "搜索性能"))
        #expect(chineseResults.first?.id == "chinese")

        let recentOnly = try await service.search(NativeSearchQuery(
            text: "project phoenix",
            temporalFilter: NativeSearchTemporalFilter(start: Date(timeIntervalSince1970: 10_000), end: Date(timeIntervalSince1970: 30_000))
        ))
        #expect(recentOnly.map(\.id).contains("subject"))
        #expect(!recentOnly.map(\.id).contains("old"))
    }

    @Test func rssEvaluationCoversTitleContentPublishedAtAndHiddenExclusion() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            rss(id: "title", title: "AI search ranking", summary: "summary", body: "content", publishedAt: Date(timeIntervalSince1970: 20_000)),
            rss(id: "content", title: "Newsletter", summary: "summary", body: "Deep dive into BM25 and CJK tokenization", publishedAt: Date(timeIntervalSince1970: 20_000)),
            rss(id: "hidden", title: "AI search ranking", summary: "hidden", body: "hidden", publishedAt: Date(timeIntervalSince1970: 20_000), hidden: true),
            rss(id: "old", title: "AI search ranking", summary: "old", body: "old", publishedAt: Date(timeIntervalSince1970: 1_000))
        ])

        let titleResults = try await service.search(NativeSearchQuery(text: "AI search ranking", sourceKinds: [.rss]))
        #expect(titleResults.first?.id == "title")
        #expect(!titleResults.map(\.id).contains("hidden"))

        let contentResults = try await service.search(NativeSearchQuery(text: "BM25 CJK", sourceKinds: [.rss]))
        #expect(contentResults.first?.id == "content")

        let recentOnly = try await service.search(NativeSearchQuery(
            text: "AI search ranking",
            sourceKinds: [.rss],
            temporalFilter: NativeSearchTemporalFilter(start: Date(timeIntervalSince1970: 10_000), end: Date(timeIntervalSince1970: 30_000))
        ))
        #expect(recentOnly.map(\.id).contains("title"))
        #expect(!recentOnly.map(\.id).contains("old"))
    }

    @Test func calendarEvaluationCoversTitleLocationIntervalAllDayAndUpcomingRanking() async throws {
        let service = NativeSourceSearchService()
        let now = Date()
        let tomorrow = now.addingTimeInterval(86_400)
        let nextWeek = now.addingTimeInterval(7 * 86_400)
        let yesterday = now.addingTimeInterval(-86_400)
        try await service.upsert([
            calendar(id: "tomorrow", title: "Project Phoenix planning", location: "West Lake Room", start: tomorrow, end: tomorrow.addingTimeInterval(3_600)),
            calendar(id: "next-week", title: "Project Phoenix planning", location: "Remote", start: nextWeek, end: nextWeek.addingTimeInterval(3_600)),
            calendar(id: "allday", title: "Company offsite", location: "Hangzhou", start: yesterday, end: tomorrow, allDay: true)
        ])

        let titleResults = try await service.search(NativeSearchQuery(text: "project phoenix", sourceKinds: [.calendar], rankingProfile: .calendarUpcoming))
        #expect(titleResults.first?.id == "tomorrow")

        let locationResults = try await service.search(NativeSearchQuery(text: "West Lake", sourceKinds: [.calendar]))
        #expect(locationResults.first?.id == "tomorrow")

        let overlapResults = try await service.search(NativeSearchQuery(
            text: "company",
            sourceKinds: [.calendar],
            temporalFilter: NativeSearchTemporalFilter(start: now, end: now.addingTimeInterval(3_600), mode: .intervalOverlapsRange)
        ))
        #expect(overlapResults.first?.id == "allday")
        #expect(overlapResults.first?.temporal.isAllDay == true)
    }

    private func mail(id: String, title: String, summary: String, participants: [String], body: String, sentAt: Date) -> NativeSearchDocument {
        NativeSearchDocument(id: id, sourceKind: .mail, externalID: id, title: title, summary: summary, body: body, participants: participants, temporal: NativeSearchTemporalMetadata(sentAt: sentAt), contentHash: id)
    }

    private func rss(id: String, title: String, summary: String, body: String, publishedAt: Date, hidden: Bool = false) -> NativeSearchDocument {
        NativeSearchDocument(id: id, sourceKind: .rss, externalID: id, title: title, summary: summary, body: body, temporal: NativeSearchTemporalMetadata(publishedAt: publishedAt), state: hidden ? ["isHidden": "true"] : [:], contentHash: id)
    }

    private func calendar(id: String, title: String, location: String, start: Date, end: Date, allDay: Bool = false) -> NativeSearchDocument {
        NativeSearchDocument(id: id, sourceKind: .calendar, externalID: id, title: title, summary: title, location: location, temporal: NativeSearchTemporalMetadata(eventStartAt: start, eventEndAt: end, isAllDay: allDay), contentHash: id)
    }
}
