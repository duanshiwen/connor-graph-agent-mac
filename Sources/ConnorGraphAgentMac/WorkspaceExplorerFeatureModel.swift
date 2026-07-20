import Foundation
import Observation
import ConnorGraphAppSupport

enum ChatListPaneMode: String, CaseIterable, Identifiable {
    case sessions
    case files

    var id: String { rawValue }
}

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
    var mode: ChatListPaneMode = .sessions
    private(set) var roots: [WorkspaceExplorerRoot] = []
    private(set) var expandedNodeIDs: Set<String> = []
    private(set) var childrenByNodeID: [String: [WorkspaceFileNode]] = [:]
    private(set) var loadingNodeIDs: Set<String> = []
    private(set) var errorsByNodeID: [String: String] = [:]
    private(set) var selectedNodeID: String?

    @ObservationIgnored private let loader: WorkspaceDirectoryLoader
    @ObservationIgnored private var tasksByNodeID: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var configurationID = ""
    @ObservationIgnored private var generation: UInt64 = 0

    init(loader: WorkspaceDirectoryLoader = WorkspaceDirectoryLoader()) {
        self.loader = loader
    }

    func configure(sessionID: String?, roots drafts: [WorkspaceRootDraft]) {
        let nextRoots = drafts.map {
            WorkspaceExplorerRoot(
                id: $0.id,
                displayName: $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? URL(fileURLWithPath: $0.path, isDirectory: true).lastPathComponent
                    : $0.displayName,
                url: URL(fileURLWithPath: $0.path, isDirectory: true),
                isPrimary: $0.isPrimary
            )
        }
        let nextConfigurationID = Self.configurationID(sessionID: sessionID, roots: nextRoots)
        guard nextConfigurationID != configurationID else { return }
        configurationID = nextConfigurationID
        generation &+= 1
        cancelAllTasks()
        roots = nextRoots
        expandedNodeIDs = []
        childrenByNodeID = [:]
        loadingNodeIDs = []
        errorsByNodeID = [:]
        selectedNodeID = nil
    }

    func toggleRoot(_ root: WorkspaceExplorerRoot) {
        toggleDirectory(nodeID: root.nodeID, root: root, directoryURL: root.url)
    }

    func toggleNode(_ node: WorkspaceFileNode) {
        guard node.isExpandable, let root = roots.first(where: { $0.id == node.rootID }) else {
            selectedNodeID = node.id
            return
        }
        toggleDirectory(nodeID: node.id, root: root, directoryURL: node.url)
    }

    func select(_ node: WorkspaceFileNode) {
        selectedNodeID = node.id
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
        Task { [weak self, loader] in
            await loader.invalidateAll()
            guard let self, self.generation == refreshGeneration else { return }
            for root in rootsToReload { self.toggleRoot(root) }
        }
    }

    func shutdown() {
        generation &+= 1
        cancelAllTasks()
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

    private func cancelAllTasks() {
        tasksByNodeID.values.forEach { $0.cancel() }
        tasksByNodeID.removeAll(keepingCapacity: true)
    }

    private static func configurationID(sessionID: String?, roots: [WorkspaceExplorerRoot]) -> String {
        ([sessionID ?? ""] + roots.map { "\($0.id)|\($0.url.path)|\($0.isPrimary)" }).joined(separator: "\n")
    }
}
