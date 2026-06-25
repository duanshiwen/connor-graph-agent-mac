import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Suite("Native Source Reference Tool Hook Tests")
struct NativeSourceReferenceToolHookTests {
    @Test func mailGetMessageRecordsDetailReference() async throws {
        let recorder = SpyNativeSourceReferenceRecorder()
        let summary = Self.mailSummary(id: "message-1", subject: "Memory OS Mail")
        let runtime = MailRuntimeFixture(messages: [summary], details: [
            "message-1": MailMessageDetail(
                summary: summary,
                body: MailMessageBody(
                    plainText: MailBodyPart(mimeType: "text/plain", text: "Mail body used by LLM", byteCount: 21),
                    redactedPreview: "Mail body preview",
                    bodyHash: "body-hash-1"
                )
            )
        ])
        let tool = MailGetMessageTool(runtime: runtime, recorder: recorder)
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: "{\"messageID\":\"message-1\",\"includeBody\":true}"),
            context: Self.context(toolCallID: "call-mail-get")
        )

        let references = await recorder.references
        #expect(references.count == 1)
        #expect(references[0].sourceKind == .mail)
        #expect(references[0].sourceRecordID == "message-1")
        #expect(references[0].referenceStrength == .detailRead)
        #expect(references[0].content.contains("Mail body used by LLM"))
        #expect(references[0].toolName == "mail_get_message")
    }

    @Test func mailSearchRecordsSummaryCandidates() async throws {
        let recorder = SpyNativeSourceReferenceRecorder()
        let runtime = MailRuntimeFixture(messages: [Self.mailSummary(id: "message-1", subject: "Memory OS Mail")], details: [:])
        let tool = MailSearchMessagesTool(runtime: runtime, recorder: recorder)
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: "{\"query\":\"Memory OS\",\"limit\":5}"),
            context: Self.context(toolCallID: "call-mail-search")
        )

        let references = await recorder.references
        #expect(references.count == 1)
        #expect(references[0].referenceStrength == .summaryCandidate)
        #expect(references[0].query == "Memory OS")
        #expect(references[0].content.contains("Snippet for message-1"))
    }

    @Test func calendarSearchRecordsFullEventResults() async throws {
        let recorder = SpyNativeSourceReferenceRecorder()
        let event = CalendarEvent(
            id: CalendarEventID(rawValue: "event-1"),
            calendarID: CalendarID(rawValue: "calendar-work"),
            title: "Memory OS Review",
            start: CalendarEventDateTime(date: Date(timeIntervalSince1970: 2_000)),
            end: CalendarEventDateTime(date: Date(timeIntervalSince1970: 3_000)),
            location: "Room A",
            notes: "Discuss source ingestion"
        )
        let runtime = InMemoryAgentCalendarRuntime(events: [event])
        let tool = CalendarSearchEventsTool(runtime: runtime, recorder: recorder)
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: "{\"query\":\"ingestion\"}"),
            context: Self.context(toolCallID: "call-calendar-search")
        )

        let references = await recorder.references
        #expect(references.count == 1)
        #expect(references[0].sourceKind == .calendar)
        #expect(references[0].referenceStrength == .fullEventResult)
        #expect(references[0].content.contains("Room A"))
        #expect(references[0].content.contains("Discuss source ingestion"))
    }

    @Test func rssGetItemRecordsDetailReference() async throws {
        let recorder = SpyNativeSourceReferenceRecorder()
        let summary = Self.rssSummary(id: "rss-1", title: "Memory OS RSS")
        let runtime = RSSRuntimeFixture(items: [summary], details: [
            "rss-1": RSSItemDetail(
                summary: summary,
                content: RSSItemContent(safeMarkdown: "# RSS Body\n\nUsed by LLM", plainText: "RSS Body Used by LLM")
            )
        ])
        let tool = RSSGetItemTool(runtime: runtime, recorder: recorder)
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: "{\"itemID\":\"rss-1\",\"includeContent\":true}"),
            context: Self.context(toolCallID: "call-rss-get")
        )

        let references = await recorder.references
        #expect(references.count == 1)
        #expect(references[0].sourceKind == .rss)
        #expect(references[0].sourceRecordID == "rss-1")
        #expect(references[0].referenceStrength == .detailRead)
        #expect(references[0].content.contains("RSS Body"))
    }

    private static func context(toolCallID: String) -> AgentToolExecutionContext {
        AgentToolExecutionContext(
            runID: "run-native-source-reference",
            sessionID: "session-native-source-reference",
            groupID: "group-native-source-reference",
            userPrompt: "test",
            toolCallID: toolCallID,
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    }

    private static func mailSummary(id: String, subject: String) -> MailMessageSummary {
        MailMessageSummary(
            id: MailMessageID(rawValue: id),
            accountID: MailAccountID(rawValue: "account-1"),
            mailboxID: MailMailboxID(rawValue: "inbox"),
            subject: subject,
            from: MailAddress(name: "Alice", email: "alice@example.com"),
            to: [MailAddress(name: "诗闻", email: "shiwen@example.com")],
            date: Date(timeIntervalSince1970: 1_000),
            snippet: "Snippet for \(id)"
        )
    }

    private static func rssSummary(id: String, title: String) -> RSSItemSummary {
        RSSItemSummary(
            id: RSSItemID(rawValue: id),
            sourceID: RSSSourceID(rawValue: "source-1"),
            title: title,
            link: URL(string: "https://example.com/\(id)"),
            author: "Author",
            publishedAt: Date(timeIntervalSince1970: 1_500),
            snippet: "Snippet for \(id)",
            contentHash: "hash-\(id)"
        )
    }
}

private actor SpyNativeSourceReferenceRecorder: NativeSourceReferenceRecording {
    private(set) var references: [NativeSourceReference] = []
    func record(_ references: [NativeSourceReference]) async {
        self.references.append(contentsOf: references)
    }
}

private struct MailRuntimeFixture: AgentMailRuntime {
    var messages: [MailMessageSummary]
    var details: [String: MailMessageDetail]

    func listAccounts(runID: String?, sessionID: String?) async throws -> [MailAccount] { [] }
    func searchMessages(_ request: MailRuntimeSearchRequestBridge, runID: String?, sessionID: String?) async throws -> [MailMessageSummary] { Array(messages.prefix(request.limit)) }
    func getMessage(id: MailMessageID, includeBody: Bool, runID: String?, sessionID: String?) async throws -> MailMessageDetail {
        guard var detail = details[id.rawValue] else { throw AgentToolError.invalidArguments("missing message") }
        if !includeBody { detail.body = nil }
        return detail
    }
    func setReadState(messageIDs: [MailMessageID], isRead: Bool, runID: String?, sessionID: String?) async throws {}
    func createDraft(accountID: MailAccountID, identityID: MailIdentityID, to: [MailAddress], cc: [MailAddress], bcc: [MailAddress], replyTo: [MailAddress], subject: String, body: String, htmlBody: String?, inReplyToMessageID: MailMessageID?, attachmentIDs: [MailAttachmentID], intentSummary: String?, runID: String?, sessionID: String?) async throws -> MailDraft {
        MailDraft(id: MailDraftID(rawValue: "draft"), accountID: accountID, identityID: identityID, to: to, cc: cc, bcc: bcc, subject: subject, body: body, htmlBody: htmlBody, replyTo: replyTo, attachmentIDs: attachmentIDs, inReplyToMessageID: inReplyToMessageID, intentSummary: intentSummary)
    }
    func sendDraft(draftID: MailDraftID, approved: Bool, runID: String?, sessionID: String?) async throws -> MailSendReceipt {
        MailSendReceipt(draftID: draftID, providerMessageID: "sent", sentAt: Date(), envelopeHash: "hash")
    }
}

private struct RSSRuntimeFixture: AgentRSSRuntime {
    var items: [RSSItemSummary]
    var details: [String: RSSItemDetail]

    func listSources(runID: String?, sessionID: String?) async throws -> [RSSSource] { [] }
    func addSource(feedURL: URL, displayName: String?, runID: String?, sessionID: String?) async throws -> RSSSource { RSSSource(id: RSSSourceID(rawValue: "source-1"), feedURL: feedURL, displayName: displayName ?? "Source") }
    func syncSource(sourceID: RSSSourceID, runID: String?, sessionID: String?) async throws -> RSSFetchResult { RSSFetchResult(runID: RSSFetchRunID(rawValue: "run"), sourceID: sourceID, insertedCount: 0, duplicateCount: 0, parseReport: RSSParseReport(format: .rss, itemCount: 0)) }
    func listItems(sourceID: RSSSourceID?, includeHidden: Bool, limit: Int, runID: String?, sessionID: String?) async throws -> [RSSItemSummary] { Array(items.prefix(limit)) }
    func searchItems(_ request: RSSRuntimeSearchRequestBridge, runID: String?, sessionID: String?) async throws -> [RSSItemSummary] { Array(items.prefix(request.limit)) }
    func getItem(id: RSSItemID, includeContent: Bool, runID: String?, sessionID: String?) async throws -> RSSItemDetail {
        guard var detail = details[id.rawValue] else { throw AgentToolError.invalidArguments("missing rss item") }
        if !includeContent { detail.content = nil }
        return detail
    }
    func setReadState(itemIDs: [RSSItemID], isRead: Bool, runID: String?, sessionID: String?) async throws {}
    func setStarState(itemIDs: [RSSItemID], isStarred: Bool, runID: String?, sessionID: String?) async throws {}
    func setHiddenState(itemIDs: [RSSItemID], isHidden: Bool, runID: String?, sessionID: String?) async throws {}
    func importOPML(_ xml: String, runID: String?, sessionID: String?) async throws -> OPMLDocument { OPMLDocument(title: "OPML", outlines: []) }
    func exportOPML(runID: String?, sessionID: String?) async throws -> String { "" }
    func evidenceCandidate(for itemID: RSSItemID) async throws -> RSSEvidenceCandidate { RSSEvidenceCandidate(sourceID: RSSSourceID(rawValue: "source-1"), itemID: itemID, redactedSummary: "", sourceHash: "") }
}
