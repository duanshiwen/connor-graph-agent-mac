import Foundation
import Observation
import ConnorGraphAppSupport
import ConnorGraphCore

@MainActor
@Observable
final class GlobalSearchFeatureModel {
    enum Destination {
        case newChat(prompt: String)
        case webSearch(query: String, url: URL)
        case chatSession(String)
        case nativeResult(NativeSearchResult)
        case browserHistoryRecord(BrowserHistoryRecord)
        case knowledgeBase(String)
        case showAll(GlobalSearchSectionKind, query: String)
    }

    var query = ""
    var isFieldFocused = false
    var isOverlayPresented = false
    private(set) var previewState: GlobalSearchPreviewState = .empty
    var selectedItem: GlobalSearchSelectableItem? = .action(.newChat)
    private(set) var timings: [GlobalSearchSectionTiming] = []
    private(set) var historyEntries: [GlobalSearchHistoryEntry]

    @ObservationIgnored private let nativeSourceSearchBackend: (any NativeSourceSearchBackend)?
    @ObservationIgnored private let sessionSearchIndexService: SessionSearchIndexService?
    @ObservationIgnored private let historyRepository: AppGlobalSearchHistoryRepository?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var sessionIndexBootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var sessionIndexMutationTask: Task<Void, Never>?
    @ObservationIgnored private var sessionIndexGeneration: UInt64 = 0
    @ObservationIgnored private var refreshGeneration: UInt64 = 0
    @ObservationIgnored private var isShutdown = false

    @ObservationIgnored var sessionsProvider: () -> [AgentSession] = { [] }
    @ObservationIgnored var fallbackNativeSearchProvider: (NativeSearchSourceKind, String, Int) -> [NativeSearchResult] = { _, _, _ in [] }
    @ObservationIgnored var prepareNativeSearchProvider: @MainActor @Sendable (NativeSearchSourceKind) async -> Void = { _ in }
    @ObservationIgnored var defaultSearchURLProvider: (String) -> URL? = { _ in nil }
    @ObservationIgnored var knowledgeMarketplaceSearchProvider: (String) async -> [CloudMarketplaceKnowledgeBase] = { _ in [] }
    @ObservationIgnored var onDestination: ((Destination) -> Void)?

    init(
        nativeSourceSearchBackend: (any NativeSourceSearchBackend)?,
        sessionSearchIndexService: SessionSearchIndexService?,
        historyRepository: AppGlobalSearchHistoryRepository?
    ) {
        self.nativeSourceSearchBackend = nativeSourceSearchBackend
        self.sessionSearchIndexService = sessionSearchIndexService
        self.historyRepository = historyRepository
        self.historyEntries = (try? historyRepository?.load()) ?? []
    }

    var selectableItems: [GlobalSearchSelectableItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && previewState == .empty {
            return historyEntries.prefix(8).map { .recentSearch($0.id) }
        }
        var items: [GlobalSearchSelectableItem] = [.action(.newChat), .action(.webSearch)]
        items.append(contentsOf: previewState.chatSessionResults.map { .chatSession($0.id) })
        items.append(contentsOf: previewState.knowledgeBaseResults.map { .knowledgeBase($0.id) })
        items.append(contentsOf: previewState.calendarResults.map { .nativeResult($0.id) })
        items.append(contentsOf: previewState.rssResults.map { .nativeResult($0.id) })
        items.append(contentsOf: previewState.mailResults.map { .nativeResult($0.id) })
        items.append(contentsOf: previewState.browserHistoryResults.prefix(3).map { .nativeResult($0.id) })
        return items
    }

    func activateField() {
        isFieldFocused = true
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isOverlayPresented = false
            selectedItem = selectableItems.first
            return
        }
        isOverlayPresented = true
        if previewState.query != trimmed { schedulePreview(for: trimmed) }
    }

    func deactivateField() { _ = finishInteraction(clearQuery: false) }

    func updateQuery(_ value: String) {
        query = value
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        previewTask?.cancel()
        guard !trimmed.isEmpty else {
            previewState = .empty
            isOverlayPresented = false
            selectedItem = selectableItems.first
            return
        }
        isOverlayPresented = true
        selectedItem = .action(.newChat)
        schedulePreview(for: trimmed)
    }

    func clear() {
        _ = finishInteraction(clearQuery: true)
        previewState = .empty
        selectedItem = .action(.newChat)
    }

    @discardableResult
    func dismissOverlay() -> Bool { finishInteraction(clearQuery: false) }

    func moveSelectionDown() { moveSelection(delta: 1) }
    func moveSelectionUp() { moveSelection(delta: -1) }

    func performSelectedItem() {
        normalizeSelection()
        guard let selectedItem else { return }
        switch selectedItem {
        case .recentSearch(let entryID):
            guard let entry = historyEntries.first(where: { $0.id == entryID }) else { return }
            selectHistoryEntry(entry)
        case .action(.newChat): performNewChat()
        case .action(.webSearch): performWebSearch()
        case .chatSession(let sessionID): openChatSession(sessionID)
        case .nativeResult(let resultID):
            let results = previewState.calendarResults + previewState.rssResults + previewState.mailResults + previewState.browserHistoryResults
            guard let result = results.first(where: { $0.id == resultID }) else { return }
            openResult(result)
        case .knowledgeBase(let id): openKnowledgeBase(id)
        }
    }

    func selectHistoryEntry(_ entry: GlobalSearchHistoryEntry) {
        recordHistoryIfNeeded(entry.query)
        updateQuery(entry.query)
    }

    func clearHistory() {
        try? historyRepository?.clear()
        historyEntries = []
        selectedItem = nil
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { isOverlayPresented = false }
    }

    func recordHistoryForTesting(query: String) { recordHistoryIfNeeded(query) }
    func installPreviewStateForTesting(_ state: GlobalSearchPreviewState) { previewState = state }

    func performNewChat() {
        let prompt = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        recordHistoryIfNeeded(prompt)
        _ = finishInteraction(clearQuery: true)
        previewState = .empty
        selectedItem = .action(.newChat)
        onDestination?(.newChat(prompt: prompt))
    }

    func performWebSearch() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let url = defaultSearchURLProvider(value) else { return }
        recordHistoryIfNeeded(value)
        dismissOverlay()
        onDestination?(.webSearch(query: value, url: url))
    }

    func openBrowserHistoryRecord(_ record: BrowserHistoryRecord) {
        dismissOverlay()
        onDestination?(.browserHistoryRecord(record))
    }

    func openChatSession(_ sessionID: String) {
        recordHistoryIfNeeded(query)
        dismissOverlay()
        onDestination?(.chatSession(sessionID))
    }

    func openResult(_ result: NativeSearchResult) {
        recordHistoryIfNeeded(query)
        dismissOverlay()
        onDestination?(.nativeResult(result))
    }

    func openKnowledgeBase(_ id: String) {
        recordHistoryIfNeeded(query)
        dismissOverlay()
        onDestination?(.knowledgeBase(id))
    }

    func showAllResults(kind: GlobalSearchSectionKind) {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        dismissOverlay()
        onDestination?(.showAll(kind, query: value))
    }

    func refreshPreview(for requestedQuery: String) async {
        if previewTask != nil {
            previewTask?.cancel()
            previewTask = nil
        }
        guard !isShutdown, isOverlayPresented, !Task.isCancelled else { return }
        let trimmed = requestedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let tokens = GlobalSearchDisplayTokenBuilder.tokens(for: trimmed)
        timings = []
        let chatStartedAt = Date()
        let chatResults = await searchChatSessions(query: trimmed, limit: 3)
        recordTiming(query: trimmed, section: "chatSessions", startedAt: chatStartedAt, returnedCount: chatResults.count, backend: sessionSearchIndexService == nil ? "fallback-scan" : "session-fts")
        guard canApply(query: trimmed, generation: generation) else { return }
        previewState = GlobalSearchPreviewState(
            query: trimmed,
            loadingSections: [.knowledgeMarketplace, .calendar, .rss, .mail, .browserHistory],
            chatSessionResults: chatResults,
            searchTokens: tokens,
            errorMessage: nil
        )
        normalizeSelection()
        async let marketplace: Void = refreshKnowledgeMarketplace(query: trimmed, tokens: tokens, generation: generation)
        async let native: Void = refreshNativeSections(query: trimmed, tokens: tokens, generation: generation)
        _ = await (marketplace, native)
    }

    private func refreshKnowledgeMarketplace(query: String, tokens: [String], generation: UInt64) async {
        let results = await knowledgeMarketplaceSearchProvider(query)
        guard canApply(query: query, generation: generation) else { return }
        var state = previewState
        state.query = query
        state.searchTokens = tokens
        state.knowledgeBaseResults = results
        state.loadingSections.remove(.knowledgeMarketplace)
        previewState = state
        normalizeSelection()
    }

    nonisolated static func userFacingErrorMessage(for error: Error) -> String? {
        if error is GlobalSearchTimeoutError { return nil }
        return String(describing: error)
    }

    nonisolated static func sectionStatusMessage(for kind: NativeSearchSourceKind, health: NativeSourceSearchHealthSnapshot) -> String? {
        if let lastError = health.lastError, !lastError.isEmpty { return "索引暂不可用" }
        if health.pendingUpdateCount > 0 { return "后台正在更新索引，先显示已索引结果" }
        if health.staleSourceKinds.contains(kind) { return "索引可能过期，先显示上次索引结果" }
        if health.documentCountBySource[kind, default: 0] == 0 { return "尚未建立索引" }
        return nil
    }

    func bootstrapSessionIndexIfNeeded(sessions: [AgentSession]) {
        guard let sessionSearchIndexService else { return }
        sessionIndexGeneration &+= 1
        let generation = sessionIndexGeneration
        sessionIndexBootstrapTask?.cancel()
        sessionIndexBootstrapTask = Task(priority: .utility) { [weak self] in
            _ = try? await sessionSearchIndexService.bootstrapIfEmpty(sessions: sessions)
            guard let self, self.sessionIndexGeneration == generation else { return }
            self.sessionIndexBootstrapTask = nil
        }
    }

    func upsertSessionIndex(_ session: AgentSession) {
        guard let sessionSearchIndexService else { return }
        let precedingMutation = sessionIndexMutationTask
        sessionIndexMutationTask = Task(priority: .utility) {
            await precedingMutation?.value
            guard !Task.isCancelled else { return }
            try? await sessionSearchIndexService.upsert(session: session)
        }
    }

    func removeSessionIndex(sessionID: String) {
        guard let sessionSearchIndexService else { return }
        let precedingMutation = sessionIndexMutationTask
        sessionIndexMutationTask = Task(priority: .utility) {
            await precedingMutation?.value
            guard !Task.isCancelled else { return }
            try? await sessionSearchIndexService.remove(sessionID: sessionID)
        }
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        refreshGeneration &+= 1
        previewTask?.cancel()
        previewTask = nil
        sessionIndexGeneration &+= 1
        sessionIndexBootstrapTask?.cancel()
        sessionIndexBootstrapTask = nil
        sessionIndexMutationTask?.cancel()
        sessionIndexMutationTask = nil
    }

    private func finishInteraction(clearQuery: Bool) -> Bool {
        let wasInteracting = isOverlayPresented || isFieldFocused
        previewTask?.cancel(); previewTask = nil; refreshGeneration &+= 1
        if clearQuery { query = "" }
        isFieldFocused = false
        isOverlayPresented = false
        return wasInteracting
    }

    private func moveSelection(delta: Int) {
        let items = selectableItems
        guard !items.isEmpty else { selectedItem = nil; return }
        let currentIndex = selectedItem.flatMap { items.firstIndex(of: $0) } ?? 0
        selectedItem = items[(currentIndex + delta + items.count) % items.count]
    }

    private func normalizeSelection() {
        let items = selectableItems
        guard !items.isEmpty else { selectedItem = nil; return }
        if let selectedItem, items.contains(selectedItem) { return }
        selectedItem = items.first
    }

    private func recordHistoryIfNeeded(_ rawQuery: String) {
        let displayQuery = AppGlobalSearchHistoryRepository.displayQuery(for: rawQuery)
        guard !displayQuery.isEmpty else { return }
        if let historyRepository, let entries = try? historyRepository.record(query: displayQuery) {
            historyEntries = entries
            return
        }
        let normalized = AppGlobalSearchHistoryRepository.normalizedQuery(for: displayQuery)
        guard !normalized.isEmpty else { return }
        if let index = historyEntries.firstIndex(where: { $0.normalizedQuery == normalized }) {
            var entry = historyEntries.remove(at: index)
            entry.query = displayQuery; entry.searchedAt = Date(); entry.useCount += 1
            historyEntries.insert(entry, at: 0)
        } else {
            historyEntries.insert(GlobalSearchHistoryEntry(id: normalized, query: displayQuery, normalizedQuery: normalized, searchedAt: Date(), useCount: 1), at: 0)
        }
        if historyEntries.count > 20 { historyEntries = Array(historyEntries.prefix(20)) }
    }

    private func schedulePreview(for value: String) {
        previewTask?.cancel()
        if previewState == .empty {
            previewState = GlobalSearchPreviewState(query: value, isLoading: false, searchTokens: GlobalSearchDisplayTokenBuilder.tokens(for: value))
        }
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            self.previewTask = nil
            await self.refreshPreview(for: value)
        }
    }

    private func canApply(query value: String, generation: UInt64) -> Bool {
        !isShutdown && isOverlayPresented && !Task.isCancelled && refreshGeneration == generation
            && query.trimmingCharacters(in: .whitespacesAndNewlines) == value
    }

    private func refreshNativeSections(query: String, tokens: [String], generation: UInt64) async {
        let limits: [NativeSearchSourceKind: Int] = [.calendar: 3, .rss: 3, .mail: 3, .browserHistory: 3]
        if let nativeSourceSearchBackend {
            let health = await nativeSourceSearchBackend.health()
            applyHealth(health, query: query, tokens: tokens, generation: generation)
            let coordinator = GlobalSearchPreviewCoordinator(
                backend: nativeSourceSearchBackend,
                timeoutMilliseconds: 250,
                prepareSearch: prepareNativeSearchProvider,
                errorMessage: Self.userFacingErrorMessage(for:)
            )
            for await sectionResult in coordinator.previewResults(query: query, limitsBySource: limits) {
                guard canApply(query: query, generation: generation) else { return }
                timings.append(sectionResult.timing)
                applySection(GlobalSearchNativeSectionResult(kind: GlobalSearchSectionKind(nativeSourceKind: sectionResult.kind), results: sectionResult.results, errorMessage: sectionResult.errorMessage, timing: sectionResult.timing), query: query, tokens: tokens, generation: generation)
            }
            return
        }
        for kind in NativeSearchSourceKind.allCases {
            guard canApply(query: query, generation: generation) else { return }
            let startedAt = Date()
            let results = fallbackNativeSearchProvider(kind, query, limits[kind] ?? 3)
            recordTiming(query: query, section: GlobalSearchSectionKind(nativeSourceKind: kind).rawValue, startedAt: startedAt, returnedCount: results.count, backend: "fallback")
            applySection(GlobalSearchNativeSectionResult(kind: GlobalSearchSectionKind(nativeSourceKind: kind), results: results, errorMessage: nil), query: query, tokens: tokens, generation: generation)
        }
    }


    private func applyHealth(_ health: NativeSourceSearchHealthSnapshot, query: String, tokens: [String], generation: UInt64) {
        guard canApply(query: query, generation: generation) else { return }
        var state = previewState; state.query = query; state.searchTokens = tokens
        for kind in NativeSearchSourceKind.allCases { state.sectionStatusMessages[GlobalSearchSectionKind(nativeSourceKind: kind)] = Self.sectionStatusMessage(for: kind, health: health) }
        previewState = state
    }

    private func applySection(_ result: GlobalSearchNativeSectionResult, query: String, tokens: [String], generation: UInt64) {
        guard canApply(query: query, generation: generation) else { return }
        var state = previewState; state.query = query; state.searchTokens = tokens; state.loadingSections.remove(result.kind)
        if let message = result.errorMessage, state.errorMessage == nil { state.errorMessage = message }
        if !result.results.isEmpty || result.errorMessage != nil { state.sectionStatusMessages[result.kind] = nil }
        switch result.kind {
        case .chatSessions: break
        case .calendar: state.calendarResults = result.results
        case .rss: state.rssResults = result.results
        case .mail: state.mailResults = result.results
        case .browserHistory: state.browserHistoryResults = result.results
        case .knowledgeMarketplace: break
        }
        previewState = state; normalizeSelection()
    }

    private func recordTiming(query: String, section: String, startedAt: Date, returnedCount: Int, backend: String) {
        timings.append(GlobalSearchSectionTiming(query: query, section: section, startedAt: startedAt, endedAt: Date(), candidateCount: returnedCount, returnedCount: returnedCount, backend: backend))
    }

    private func searchChatSessions(query: String, limit: Int) async -> [GlobalSearchSessionResult] {
        if let sessionSearchIndexService,
           let indexed = try? await sessionSearchIndexService.search(query: query, limit: limit),
           !indexed.isEmpty {
            return indexed.map { GlobalSearchSessionResult(id: $0.id, title: $0.title, snippet: $0.snippet, updatedAt: $0.updatedAt, messageCount: $0.messageCount) }
        }
        let terms = Self.matchTerms(for: query)
        guard !terms.isEmpty else { return [] }
        return sessionsProvider().compactMap { session -> (GlobalSearchSessionResult, Double)? in
            let titleScore = Self.matchScore(text: session.title, terms: terms, weight: 20)
            var bestMessageScore = 0.0; var bestSnippet = session.messages.last?.content ?? session.title
            for message in session.messages {
                let score = Self.matchScore(text: message.content, terms: terms, weight: message.role == .user ? 8 : 5)
                if score > bestMessageScore { bestMessageScore = score; bestSnippet = Self.snippet(text: message.content, terms: terms) }
            }
            let total = titleScore + bestMessageScore
            guard total > 0 else { return nil }
            let snippet = titleScore > 0 && bestMessageScore == 0 ? "最近更新：\(session.updatedAt.connorLocalFormatted(date: .medium, time: .short))" : bestSnippet
            return (GlobalSearchSessionResult(id: session.id, title: session.title.isEmpty ? "新对话" : session.title, snippet: snippet, updatedAt: session.updatedAt, messageCount: session.messages.count), total + min(3, Date().timeIntervalSince(session.updatedAt) / -86_400_000))
        }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.updatedAt > $1.0.updatedAt }.prefix(limit).map(\.0)
    }

    private static func matchTerms(for query: String) -> [String] {
        let normalized = NativeSearchQueryNormalizer.normalize(query)
        var seen: Set<String> = []
        let terms = normalized.scoringTokens.map(\.value).filter { !$0.isEmpty }.filter { $0.count >= 2 || query.count <= 2 }.filter { seen.insert($0).inserted }
        if !terms.isEmpty { return terms }
        return query.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init).filter { !$0.isEmpty }
    }

    private static func matchScore(text: String, terms: [String], weight: Double) -> Double {
        let lower = text.lowercased(); let matched = terms.filter { lower.localizedCaseInsensitiveContains($0) }
        guard !matched.isEmpty, matched.count >= min(max(terms.count, 1), 2) else { return 0 }
        let coverage = Double(matched.count) / Double(max(terms.count, 1))
        let bonus = matched.reduce(0.0) { $0 + (lower == $1.lowercased() ? 2 : 0) }
        return weight * (0.75 + coverage) + bonus
    }

    private static func snippet(text: String, terms: [String], maxLength: Int = 120) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lower = trimmed.lowercased()
        guard let term = terms.first(where: { lower.localizedCaseInsensitiveContains($0) }), let range = lower.range(of: term.lowercased()) else { return String(trimmed.prefix(maxLength)) }
        let distance = lower.distance(from: lower.startIndex, to: range.lowerBound); let start = max(0, distance - 36); let end = min(trimmed.count, start + maxLength)
        return String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: start)..<trimmed.index(trimmed.startIndex, offsetBy: end)])
    }
}
