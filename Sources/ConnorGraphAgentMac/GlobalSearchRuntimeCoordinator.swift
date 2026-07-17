import Foundation
import ConnorGraphCore
import ConnorGraphSearch
import ConnorGraphAppSupport

@MainActor
final class GlobalSearchRuntimeCoordinator {
    private let search: GlobalSearchFeatureModel
    private let shell: AppShellFeatureModel
    private let chat: ChatFeatureModel
    private let chatSessions: any ChatSessionCommanding
    private let chatRun: any ChatRunCommanding
    private let browser: BrowserFeatureModel
    private let calendar: CalendarFeatureModel
    private let rss: RSSFeatureModel
    private let mail: MailFeatureModel
    private let appSettings: AppSettingsFeatureModel
    private let knowledgeMarketplace: CloudKnowledgeMarketplaceStore

    init(
        search: GlobalSearchFeatureModel,
        shell: AppShellFeatureModel,
        chat: ChatFeatureModel,
        chatSessions: any ChatSessionCommanding,
        chatRun: any ChatRunCommanding,
        browser: BrowserFeatureModel,
        calendar: CalendarFeatureModel,
        rss: RSSFeatureModel,
        mail: MailFeatureModel,
        knowledgeMarketplace: CloudKnowledgeMarketplaceStore,
        appSettings: AppSettingsFeatureModel
    ) {
        self.search = search
        self.shell = shell
        self.chat = chat
        self.chatSessions = chatSessions
        self.chatRun = chatRun
        self.browser = browser
        self.calendar = calendar
        self.rss = rss
        self.mail = mail
        self.knowledgeMarketplace = knowledgeMarketplace
        self.appSettings = appSettings
    }

    func activate() {
        search.sessionsProvider = { [weak chat] in chat?.sessions.allSessions ?? [] }
        search.fallbackNativeSearchProvider = { [weak self] kind, query, limit in
            self?.fallbackResults(kind: kind, query: query, limit: limit) ?? []
        }
        search.defaultSearchURLProvider = { [weak appSettings] query in
            appSettings?.defaultSearchEngine.searchURL(for: query)
        }
        search.knowledgeMarketplaceSearchProvider = { [weak knowledgeMarketplace] query in
            await knowledgeMarketplace?.resultsForGlobalSearch(query: query) ?? []
        }
        search.onDestination = { [weak self] destination in
            self?.handle(destination)
        }
    }

    private func fallbackResults(kind: NativeSearchSourceKind, query: String, limit: Int) -> [NativeSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        switch kind {
        case .calendar:
            let normalized = trimmed.lowercased()
            return calendar.events
                .filter { event in
                    guard !normalized.isEmpty else { return true }
                    return event.title.lowercased().contains(normalized)
                        || (event.location?.lowercased().contains(normalized) ?? false)
                        || (event.notes?.lowercased().contains(normalized) ?? false)
                        || event.attendees.contains { attendee in
                            (attendee.name?.lowercased().contains(normalized) ?? false)
                                || (attendee.email?.lowercased().contains(normalized) ?? false)
                        }
                }
                .sorted { $0.start.date < $1.start.date }
                .prefix(limit)
                .map { event in
                    NativeSearchResult(
                        id: "calendar:\(event.id.rawValue)", sourceKind: .calendar,
                        externalID: event.id.rawValue, sourceInstanceID: event.calendarID.rawValue,
                        title: event.title,
                        snippet: [event.location, event.notes].compactMap { $0 }.joined(separator: " · "),
                        score: 1, lexicalScore: 1, freshnessScore: 0, fieldScore: 0,
                        temporal: NativeSearchTemporalMetadata(primaryTime: event.start.date, primaryTimeKind: .eventStartAt, eventStartAt: event.start.date, eventEndAt: event.end.date, indexedAt: now),
                        resultTimeLabel: event.start.date.connorLocalFormatted(date: .medium, time: .short)
                    )
                }
        case .rss:
            return rss.presentation.items(sourceID: nil, query: trimmed).prefix(limit).map { item in
                NativeSearchResult(
                    id: "rss:\(item.id.rawValue)", sourceKind: .rss,
                    externalID: item.id.rawValue, sourceInstanceID: item.sourceID.rawValue,
                    title: item.title, snippet: item.snippet,
                    score: 1, lexicalScore: 1, freshnessScore: 0, fieldScore: 0,
                    temporal: NativeSearchTemporalMetadata(primaryTime: item.publishedAt, primaryTimeKind: .publishedAt, publishedAt: item.publishedAt, fetchedAt: item.fetchedAt, indexedAt: now),
                    resultTimeLabel: item.publishedAt.connorLocalFormatted(date: .medium, time: .short)
                )
            }
        case .mail:
            let normalized = trimmed.lowercased()
            return mail.presentation.messages
                .filter { message in
                    guard !normalized.isEmpty else { return true }
                    return message.subject.lowercased().contains(normalized)
                        || message.snippet.lowercased().contains(normalized)
                        || message.from.email.lowercased().contains(normalized)
                        || (message.from.name?.lowercased().contains(normalized) ?? false)
                        || message.to.contains { $0.email.lowercased().contains(normalized) || ($0.name?.lowercased().contains(normalized) ?? false) }
                }
                .sorted { $0.date > $1.date }
                .prefix(limit)
                .map { message in
                    NativeSearchResult(
                        id: "mail:\(message.id.rawValue)", sourceKind: .mail,
                        externalID: message.id.rawValue, sourceInstanceID: message.accountID.rawValue,
                        title: message.subject.isEmpty ? "(No subject)" : message.subject,
                        snippet: [message.from.name ?? message.from.email, message.snippet].filter { !$0.isEmpty }.joined(separator: " · "),
                        score: 1, lexicalScore: 1, freshnessScore: 0, fieldScore: 0,
                        temporal: NativeSearchTemporalMetadata(primaryTime: message.date, primaryTimeKind: .sentAt, receivedAt: message.date, sentAt: message.date, indexedAt: now),
                        resultTimeLabel: message.date.connorLocalFormatted(date: .medium, time: .short)
                    )
                }
        case .browserHistory:
            return browser.fallbackSearchResults(query: trimmed, now: now, limit: limit)
        }
    }

    private func handle(_ destination: GlobalSearchFeatureModel.Destination) {
        switch destination {
        case .newChat(let prompt):
            chatSessions.newChatSession()
            shell.selection = .agentChat
            Task { @MainActor [weak chatRun] in
                await chatRun?.submitChat(prompt: prompt, clearComposer: false, displayPrompt: prompt, attachments: [], personReferences: [])
            }
        case .webSearch(let url):
            browser.openURL(url)
        case .chatSession(let sessionID):
            shell.selection = .agentChat
            chatSessions.selectChatSession(sessionID)
        case .nativeResult(let result):
            open(result)
        case .browserHistoryRecord(let record):
            browser.navigateToHistoryRecord(record)
        case .knowledgeBase(let id):
            shell.selection = .knowledgeMarketplace
            Task { await knowledgeMarketplace.loadDetail(id: id) }
        case .showAll(let kind, let query):
            switch kind {
            case .chatSessions:
                chat.sessions.searchQuery = query
                browser.isVisible = false
                shell.selection = .agentChat
            case .calendar:
                calendar.searchQuery = query
                shell.selection = .calendar
            case .rss:
                rss.searchQuery = query
                shell.selection = .rss
            case .mail:
                mail.searchQuery = query
                shell.selection = .mail
            case .browserHistory:
                browser.openHistorySearch(query: query)
            case .knowledgeMarketplace:
                shell.selection = .knowledgeMarketplace
                Task { await knowledgeMarketplace.search(query: query) }
            }
        }
    }

    private func open(_ result: NativeSearchResult) {
        switch result.sourceKind {
        case .calendar:
            shell.selection = .calendar
            calendar.selectEvent(id: CalendarEventID(rawValue: result.externalID))
        case .rss:
            shell.selection = .rss
            rss.selectItem(id: RSSItemID(rawValue: result.externalID))
        case .mail:
            shell.selection = .mail
            mail.openSearchResult(result)
        case .browserHistory:
            if let id = UUID(uuidString: result.externalID), let record = browser.historyRecord(id: id) {
                browser.navigateToHistoryRecord(record)
            } else {
                browser.openHistorySearch(query: "")
            }
        }
    }
}
