import Foundation
import Observation
import ConnorGraphAppSupport

struct WorkspaceExplorerRoot: Identifiable, Equatable {
    var id: String
    var displayName: String
    var url: URL
    var isPrimary: Bool

    var nodeID: String { "root:\(id)" }
}

@MainActor
@Observable
final class WorkspaceExplorerFeatureModel {
    private(set) var isTreePresented = false
    private(set) var roots: [WorkspaceExplorerRoot] = []
    private(set) var expandedNodeIDs: Set<String> = []
    private(set) var childrenByNodeID: [String: [WorkspaceFileNode]] = [:]
    private(set) var loadingNodeIDs: Set<String> = []
    private(set) var errorsByNodeID: [String: String] = [:]
    private(set) var selectedNodeID: String?
    private(set) var previewModel: WorkspaceFilePreviewModel?
    private(set) var isLoadingPreview = false
    private(set) var gitStatusesByPath: [String: WorkspaceGitFileStatus] = [:]

    @ObservationIgnored private let loader: WorkspaceDirectoryLoader
    @ObservationIgnored private let previewLoader: WorkspaceFilePreviewLoader
    @ObservationIgnored private let gitStatusLoader: WorkspaceGitStatusLoader
    @ObservationIgnored private var tasksByNodeID: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var gitStatusTask: Task<Void, Never>?
    @ObservationIgnored private var previewTextByteLimit = WorkspaceFilePreviewLoader.defaultMaximumTextByteCount
    @ObservationIgnored private var configurationID = ""
    @ObservationIgnored private var activeSessionID: String?
    @ObservationIgnored private var cachedTreeStatesBySessionID: [String: CachedTreeState] = [:]
    @ObservationIgnored private var cachedSessionIDsByRecency: [String] = []
    @ObservationIgnored private var generation: UInt64 = 0

    private struct CachedTreeState {
        var workingDirectoryPath: String
        var roots: [WorkspaceExplorerRoot]
        var expandedNodeIDs: Set<String>
        var childrenByNodeID: [String: [WorkspaceFileNode]]
        var errorsByNodeID: [String: String]
        var gitStatusesByPath: [String: WorkspaceGitFileStatus]
    }

    private static let maximumCachedSessionCount = 5

    init(
        loader: WorkspaceDirectoryLoader = WorkspaceDirectoryLoader(),
        previewLoader: WorkspaceFilePreviewLoader = WorkspaceFilePreviewLoader(),
        gitStatusLoader: WorkspaceGitStatusLoader = WorkspaceGitStatusLoader()
    ) {
        self.loader = loader
        self.previewLoader = previewLoader
        self.gitStatusLoader = gitStatusLoader
    }

    func presentTree(sessionID: String?, workingDirectoryPath: String) {
        configure(sessionID: sessionID, workingDirectoryPath: workingDirectoryPath)
        isTreePresented = true
    }

    func toggleTree(sessionID: String?, workingDirectoryPath: String) {
        if isTreePresented {
            dismissTree()
        } else {
            presentTree(sessionID: sessionID, workingDirectoryPath: workingDirectoryPath)
        }
    }

    func dismissTree() {
        isTreePresented = false
    }

    func configure(sessionID: String?, workingDirectoryPath: String) {
        let rawPath = workingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = rawPath.isEmpty ? "" : URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL.path
        let nextRoots: [WorkspaceExplorerRoot]
        if let sessionID, !path.isEmpty {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            nextRoots = [WorkspaceExplorerRoot(
                id: "session-working-directory:\(sessionID)",
                displayName: url.lastPathComponent.isEmpty ? path : url.lastPathComponent,
                url: url,
                isPrimary: true
            )]
        } else {
            nextRoots = []
        }
        let nextConfigurationID = Self.configurationID(sessionID: sessionID, roots: nextRoots)
        guard nextConfigurationID != configurationID else { return }
        cacheActiveTreeState()
        configurationID = nextConfigurationID
        activeSessionID = sessionID
        generation &+= 1
        cancelAllTasks()
        previewTask?.cancel()
        previewTask = nil
        gitStatusTask?.cancel()
        gitStatusTask = nil
        if let sessionID,
           let cached = cachedTreeStatesBySessionID[sessionID],
           cached.workingDirectoryPath == path {
            roots = cached.roots
            expandedNodeIDs = cached.expandedNodeIDs
            childrenByNodeID = cached.childrenByNodeID
            errorsByNodeID = cached.errorsByNodeID
            gitStatusesByPath = cached.gitStatusesByPath
            markSessionCacheAsRecent(sessionID)
        } else {
            if let sessionID {
                cachedTreeStatesBySessionID[sessionID] = nil
                cachedSessionIDsByRecency.removeAll { $0 == sessionID }
            }
            roots = nextRoots
            expandedNodeIDs = []
            childrenByNodeID = [:]
            errorsByNodeID = [:]
            gitStatusesByPath = [:]
        }
        loadingNodeIDs = []
        selectedNodeID = nil
        previewModel = nil
        isLoadingPreview = false
        loadGitStatuses()
    }

    func toggleRoot(_ root: WorkspaceExplorerRoot) {
        toggleDirectory(nodeID: root.nodeID, root: root, directoryURL: root.url)
    }

    func toggleNode(_ node: WorkspaceFileNode) {
        guard node.isExpandable, let root = roots.first(where: { $0.id == node.rootID }) else {
            select(node)
            return
        }
        toggleDirectory(nodeID: node.id, root: root, directoryURL: node.url)
    }

    func activateNode(
        _ node: WorkspaceFileNode,
        openHTMLPreview: (WorkspaceFileNode, WorkspaceExplorerRoot) -> Void
    ) {
        if node.isExpandable {
            toggleNode(node)
        } else if WorkspaceFilePreviewLoader.renderer(for: node.url) == .html,
                  let root = roots.first(where: { $0.id == node.rootID }) {
            selectedNodeID = node.id
            closePreview()
            openHTMLPreview(node, root)
        } else {
            select(node)
        }
    }

    func select(_ node: WorkspaceFileNode) {
        selectedNodeID = node.id
        previewTextByteLimit = WorkspaceFilePreviewLoader.defaultMaximumTextByteCount
        previewModel = nil
        loadPreview(node)
    }

    func loadMorePreview() {
        guard !isLoadingPreview, let previewModel, previewModel.isTruncated else { return }
        previewTextByteLimit += WorkspaceFilePreviewLoader.defaultMaximumTextByteCount
        loadPreview(previewModel.node)
    }

    private func loadPreview(_ node: WorkspaceFileNode) {
        previewTask?.cancel()
        isLoadingPreview = true
        let requestGeneration = generation
        let textByteLimit = previewTextByteLimit
        previewTask = Task { [weak self, previewLoader] in
            let preview = await previewLoader.load(node, textByteLimit: textByteLimit)
            guard !Task.isCancelled else { return }
            self?.finishPreview(preview, generation: requestGeneration)
        }
    }

    func closePreview() {
        previewTask?.cancel()
        previewTask = nil
        previewModel = nil
        isLoadingPreview = false
    }

    func collapseAll() {
        cancelAllTasks()
        expandedNodeIDs = []
        loadingNodeIDs = []
    }

    func refresh() {
        let rootsToReload = roots.filter { expandedNodeIDs.contains($0.nodeID) }
        generation &+= 1
        let refreshGeneration = generation
        cancelAllTasks()
        expandedNodeIDs = []
        childrenByNodeID = [:]
        loadingNodeIDs = []
        errorsByNodeID = [:]
        gitStatusesByPath = [:]
        loadGitStatuses()
        Task { [weak self, loader] in
            await loader.invalidateAll()
            guard let self, self.generation == refreshGeneration else { return }
            for root in rootsToReload { self.toggleRoot(root) }
        }
    }

    func shutdown() {
        generation &+= 1
        cancelAllTasks()
        gitStatusTask?.cancel()
        gitStatusTask = nil
        closePreview()
        isTreePresented = false
        activeSessionID = nil
        cachedTreeStatesBySessionID = [:]
        cachedSessionIDsByRecency = []
    }

    func gitStatus(for node: WorkspaceFileNode) -> WorkspaceGitFileStatus? {
        gitStatusesByPath[node.url.standardizedFileURL.path]
    }

    private func loadGitStatuses() {
        gitStatusTask?.cancel()
        guard let root = roots.first else { return }
        let requestGeneration = generation
        gitStatusTask = Task { [weak self, gitStatusLoader] in
            let statuses = await gitStatusLoader.statuses(for: root.url)
            guard !Task.isCancelled else { return }
            self?.finishLoadingGitStatuses(statuses, generation: requestGeneration)
        }
    }

    private func finishLoadingGitStatuses(
        _ statuses: [String: WorkspaceGitFileStatus],
        generation requestGeneration: UInt64
    ) {
        guard requestGeneration == generation else { return }
        gitStatusesByPath = statuses
        gitStatusTask = nil
    }

    private func toggleDirectory(nodeID: String, root: WorkspaceExplorerRoot, directoryURL: URL) {
        if expandedNodeIDs.contains(nodeID) {
            expandedNodeIDs.remove(nodeID)
            tasksByNodeID.removeValue(forKey: nodeID)?.cancel()
            loadingNodeIDs.remove(nodeID)
            return
        }
        expandedNodeIDs.insert(nodeID)
        guard childrenByNodeID[nodeID] == nil else { return }
        loadChildren(nodeID: nodeID, root: root, directoryURL: directoryURL)
    }

    private func loadChildren(nodeID: String, root: WorkspaceExplorerRoot, directoryURL: URL) {
        tasksByNodeID[nodeID]?.cancel()
        loadingNodeIDs.insert(nodeID)
        errorsByNodeID[nodeID] = nil
        let requestGeneration = generation
        tasksByNodeID[nodeID] = Task { [weak self, loader] in
            do {
                let children = try await loader.children(rootID: root.id, rootURL: root.url, directoryURL: directoryURL)
                guard !Task.isCancelled else { return }
                self?.finishLoading(children, nodeID: nodeID, generation: requestGeneration)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishLoading(error, nodeID: nodeID, generation: requestGeneration)
            }
        }
    }

    private func finishLoading(_ children: [WorkspaceFileNode], nodeID: String, generation requestGeneration: UInt64) {
        guard requestGeneration == generation else { return }
        childrenByNodeID[nodeID] = children
        loadingNodeIDs.remove(nodeID)
        tasksByNodeID[nodeID] = nil
    }

    private func finishLoading(_ error: Error, nodeID: String, generation requestGeneration: UInt64) {
        guard requestGeneration == generation else { return }
        errorsByNodeID[nodeID] = error.localizedDescription
        loadingNodeIDs.remove(nodeID)
        tasksByNodeID[nodeID] = nil
    }

    private func finishPreview(_ preview: WorkspaceFilePreviewModel, generation requestGeneration: UInt64) {
        guard requestGeneration == generation else { return }
        previewModel = preview
        isLoadingPreview = false
        previewTask = nil
    }

    private func cancelAllTasks() {
        tasksByNodeID.values.forEach { $0.cancel() }
        tasksByNodeID.removeAll(keepingCapacity: true)
    }

    private func cacheActiveTreeState() {
        guard let activeSessionID, let root = roots.first else { return }
        cachedTreeStatesBySessionID[activeSessionID] = CachedTreeState(
            workingDirectoryPath: root.url.path,
            roots: roots,
            expandedNodeIDs: expandedNodeIDs,
            childrenByNodeID: childrenByNodeID,
            errorsByNodeID: errorsByNodeID,
            gitStatusesByPath: gitStatusesByPath
        )
        markSessionCacheAsRecent(activeSessionID)
        while cachedSessionIDsByRecency.count > Self.maximumCachedSessionCount {
            let evictedSessionID = cachedSessionIDsByRecency.removeLast()
            cachedTreeStatesBySessionID[evictedSessionID] = nil
        }
    }

    private func markSessionCacheAsRecent(_ sessionID: String) {
        cachedSessionIDsByRecency.removeAll { $0 == sessionID }
        cachedSessionIDsByRecency.insert(sessionID, at: 0)
    }

    private static func configurationID(sessionID: String?, roots: [WorkspaceExplorerRoot]) -> String {
        ([sessionID ?? ""] + roots.map { "\($0.id)|\($0.url.path)|\($0.isPrimary)" }).joined(separator: "\n")
    }
}
