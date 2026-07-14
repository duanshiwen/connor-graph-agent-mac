import Foundation
import Observation
import ConnorGraphCore
import ConnorGraphAppSupport

@MainActor
@Observable
final class RSSFeatureModel {
    enum SourceSetChangeScope {
        case rssOnly
        case allSources
    }

    enum Event {
        case operationSucceeded
        case operationFailed(String)
    }

    var presentation: NativeRSSBrowserPresentation = .empty
    var searchQuery = ""
    var selectedSourceID: RSSSourceID?
    var selectedItemID: RSSItemID?
    var isPresentingAddSourceSheet = false
    var editingSource: RSSSource?
    var pendingSourceDeletion: RSSSource?
    private(set) var errorMessage: String?

    @ObservationIgnored private let runtime: RSSRuntime
    @ObservationIgnored private var reloadGeneration: UInt64 = 0
    @ObservationIgnored private var ownedTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var isShutdown = false
    @ObservationIgnored var sessionIDProvider: @MainActor () -> String? = { nil }
    @ObservationIgnored var sourceSetChanged: @MainActor (SourceSetChangeScope) async throws -> Void = { _ in }
    @ObservationIgnored var onFollowRequest: ((RSSFollowRequest) -> Void)?
    @ObservationIgnored var onEvent: ((Event) -> Void)?

    init(runtime: RSSRuntime) {
        self.runtime = runtime
    }

    var repository: any RSSSourceRepository { runtime.repository }
    var agentRuntime: RSSRuntime { runtime }

    func reload(runID: String? = nil, sessionID: String? = nil) async {
        guard !isShutdown else { return }
        reloadGeneration &+= 1
        let generation = reloadGeneration
        let auditSessionID = sessionID ?? sessionIDProvider()
        do {
            async let sourcesRequest = runtime.listSources(runID: runID, sessionID: auditSessionID)
            async let itemsRequest = runtime.listItems(
                sourceID: nil,
                includeHidden: false,
                limit: 200,
                runID: runID,
                sessionID: auditSessionID
            )
            let (sources, items) = try await (sourcesRequest, itemsRequest)
            guard !Task.isCancelled, !isShutdown, generation == reloadGeneration else { return }
            presentation = NativeRSSBrowserPresentation(sources: sources, items: items)
            applySelectionFallback(sources: sources, items: items)
        } catch is CancellationError {
            return
        } catch {
            guard !isShutdown, generation == reloadGeneration else { return }
            reportFailure(String(describing: error))
        }
    }

    func selectItem(_ item: RSSItemSummary) {
        selectedSourceID = item.sourceID
        selectedItemID = item.id
        guard !item.state.isRead else { return }
        setReadState([item.id], isRead: true)
    }

    func selectItem(id: RSSItemID) {
        if let item = presentation.item(id: id) {
            selectItem(item)
        } else {
            selectedItemID = id
        }
    }

    func setReadState(_ itemIDs: [RSSItemID], isRead: Bool) {
        guard !itemIDs.isEmpty, !isShutdown else { return }
        let targetIDs = Set(itemIDs)
        let updatedItems = presentation.items.map { item in
            guard targetIDs.contains(item.id), item.state.isRead != isRead else { return item }
            var copy = item
            copy.state.isRead = isRead
            return copy
        }
        presentation = NativeRSSBrowserPresentation(sources: presentation.sources, items: updatedItems)
        startOwnedTask { [weak self] in
            guard let self else { return }
            do {
                try await self.runtime.setReadState(
                    itemIDs: itemIDs,
                    isRead: isRead,
                    runID: nil,
                    sessionID: self.sessionIDProvider()
                )
                await self.reload()
            } catch is CancellationError {
                return
            } catch {
                self.reportFailure(String(describing: error))
                await self.reload()
            }
        }
    }

    func addSourceAndSync(feedURL: URL, displayName: String?) async throws {
        let sessionID = sessionIDProvider()
        let source = try await runtime.addSource(
            feedURL: feedURL,
            displayName: displayName,
            runID: nil,
            sessionID: sessionID
        )
        selectedSourceID = source.id
        do {
            _ = try await runtime.syncSource(sourceID: source.id, runID: nil, sessionID: sessionID)
            reportSuccess()
        } catch {
            reportFailure("RSS 订阅源已添加，但首次抓取失败：\(error.localizedDescription)")
        }
        try await sourceSetChanged(.rssOnly)
        await reload()
    }

    func updateSource(sourceID: RSSSourceID, feedURL: URL, displayName: String?) async throws {
        let previousItemID = selectedItemID
        let previousItemBelongsToSource = previousItemID
            .flatMap { presentation.item(id: $0) }
            .map { $0.sourceID == sourceID } ?? false
        let source = try await runtime.updateSource(
            sourceID: sourceID,
            feedURL: feedURL,
            displayName: displayName,
            runID: nil,
            sessionID: sessionIDProvider()
        )
        selectedSourceID = source.id
        if previousItemBelongsToSource, source.feedURL == feedURL {
            selectedItemID = previousItemID
        }
        try await sourceSetChanged(.rssOnly)
        reportSuccess()
        await reload()
    }

    func deleteSource(_ source: RSSSource) {
        guard !isShutdown else { return }
        startOwnedTask { [weak self] in
            guard let self else { return }
            do {
                try await self.runtime.deleteSource(
                    sourceID: source.id,
                    runID: nil,
                    sessionID: self.sessionIDProvider()
                )
                guard !Task.isCancelled, !self.isShutdown else { return }
                if self.selectedSourceID == source.id { self.selectedSourceID = nil }
                if let selectedItemID = self.selectedItemID,
                   self.presentation.item(id: selectedItemID)?.sourceID == source.id {
                    self.selectedItemID = nil
                }
                try await self.sourceSetChanged(.allSources)
                self.pendingSourceDeletion = nil
                self.reportSuccess()
                await self.reload()
            } catch is CancellationError {
                return
            } catch {
                self.pendingSourceDeletion = nil
                self.reportFailure(String(describing: error))
                await self.reload()
            }
        }
    }

    func followItem(_ item: RSSItemSummary) {
        guard let url = item.link else {
            reportFailure("这篇 RSS 文章没有可打开的原文链接。")
            return
        }
        if !item.state.isRead {
            setReadState([item.id], isRead: true)
        }
        reportSuccess()
        onFollowRequest?(RSSFollowRequest(itemID: item.id.rawValue, title: item.title, url: url))
    }

    func refreshForScheduledTask(sourceInstanceID: String?, runID: String?) async throws -> String {
        let sessionID = sessionIDProvider()
        if let sourceInstanceID, !sourceInstanceID.isEmpty {
            let result = try await runtime.syncSource(
                sourceID: RSSSourceID(rawValue: sourceInstanceID),
                runID: runID,
                sessionID: sessionID
            )
            await reload(runID: runID, sessionID: sessionID)
            return "RSS refreshed source \(sourceInstanceID); inserted \(result.insertedCount), duplicates \(result.duplicateCount)"
        }

        let sources = try await runtime.listSources(runID: runID, sessionID: sessionID)
        var inserted = 0
        var duplicates = 0
        for source in sources {
            let result = try await runtime.syncSource(sourceID: source.id, runID: runID, sessionID: sessionID)
            inserted += result.insertedCount
            duplicates += result.duplicateCount
        }
        await reload(runID: runID, sessionID: sessionID)
        return "RSS refreshed \(sources.count) sources; inserted \(inserted), duplicates \(duplicates)"
    }

    func waitForPendingOperations() async {
        while !ownedTasks.isEmpty {
            let tasks = Array(ownedTasks.values)
            for task in tasks { await task.value }
        }
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        reloadGeneration &+= 1
        for task in ownedTasks.values { task.cancel() }
        ownedTasks.removeAll()
    }

    private func applySelectionFallback(sources: [RSSSource], items: [RSSItemSummary]) {
        if let selectedSourceID, !sources.contains(where: { $0.id == selectedSourceID }) {
            self.selectedSourceID = sources.first?.id
        } else if selectedSourceID == nil {
            selectedSourceID = sources.first?.id
        }
        if let selectedItemID, !items.contains(where: { $0.id == selectedItemID }) {
            self.selectedItemID = items.first?.id
        } else if selectedItemID == nil {
            selectedItemID = items.first?.id
        }
    }

    private func startOwnedTask(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        ownedTasks[id] = Task { @MainActor [weak self] in
            await operation()
            self?.ownedTasks[id] = nil
        }
    }

    private func reportSuccess() {
        errorMessage = nil
        onEvent?(.operationSucceeded)
    }

    private func reportFailure(_ message: String) {
        errorMessage = message
        onEvent?(.operationFailed(message))
    }
}
