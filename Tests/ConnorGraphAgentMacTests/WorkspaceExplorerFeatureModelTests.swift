import Foundation
import Testing
@testable import ConnorGraphAgentMac

@Suite("Workspace Explorer Feature Model")
@MainActor
struct WorkspaceExplorerFeatureModelTests {
    @Test("Expanding a root loads only its direct children")
    func expandsRoot() async throws {
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try "hello".write(to: rootURL.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        let model = WorkspaceExplorerFeatureModel()
        model.configure(sessionID: "session", workingDirectoryPath: rootURL.path)

        let root = try #require(model.roots.first)
        model.toggleRoot(root)
        try await waitUntil { !model.loadingNodeIDs.contains(root.nodeID) }

        #expect(model.expandedNodeIDs.contains(root.nodeID))
        #expect(model.childrenByNodeID[root.nodeID]?.map(\.name) == ["hello.txt"])
    }

    @Test("Changing sessions drops expanded and selected state")
    func resetsForSessionChange() throws {
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let model = WorkspaceExplorerFeatureModel()
        model.configure(sessionID: "first", workingDirectoryPath: rootURL.path)
        let root = try #require(model.roots.first)
        model.toggleRoot(root)

        model.configure(sessionID: "second", workingDirectoryPath: rootURL.path)

        #expect(model.expandedNodeIDs.isEmpty)
        #expect(model.childrenByNodeID.isEmpty)
        #expect(model.selectedNodeID == nil)
    }

    @Test("Switching back restores only that session's expanded tree")
    func restoresTreeStatePerSession() async throws {
        let firstRootURL = try temporaryDirectory()
        let secondRootURL = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstRootURL)
            try? FileManager.default.removeItem(at: secondRootURL)
        }
        try "first".write(to: firstRootURL.appendingPathComponent("first.txt"), atomically: true, encoding: .utf8)
        let model = WorkspaceExplorerFeatureModel()
        model.configure(sessionID: "first", workingDirectoryPath: firstRootURL.path)
        let firstRoot = try #require(model.roots.first)
        model.toggleRoot(firstRoot)
        try await waitUntil { model.childrenByNodeID[firstRoot.nodeID] != nil }

        model.configure(sessionID: "second", workingDirectoryPath: secondRootURL.path)
        #expect(model.expandedNodeIDs.isEmpty)
        #expect(model.childrenByNodeID.isEmpty)

        model.configure(sessionID: "first", workingDirectoryPath: firstRootURL.path)
        #expect(model.expandedNodeIDs == Set([firstRoot.nodeID]))
        #expect(model.childrenByNodeID[firstRoot.nodeID]?.map(\.name) == ["first.txt"])
    }

    @Test("Changing sessions closes the active file preview")
    func closesPreviewOnSessionChange() async throws {
        let firstRootURL = try temporaryDirectory()
        let secondRootURL = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstRootURL)
            try? FileManager.default.removeItem(at: secondRootURL)
        }
        try "preview".write(to: firstRootURL.appendingPathComponent("preview.txt"), atomically: true, encoding: .utf8)
        let model = WorkspaceExplorerFeatureModel()
        model.configure(sessionID: "first", workingDirectoryPath: firstRootURL.path)
        let firstRoot = try #require(model.roots.first)
        model.toggleRoot(firstRoot)
        try await waitUntil { model.childrenByNodeID[firstRoot.nodeID] != nil }
        model.select(try #require(model.childrenByNodeID[firstRoot.nodeID]?.first))
        try await waitUntil { model.previewModel != nil }

        model.configure(sessionID: "second", workingDirectoryPath: secondRootURL.path)

        #expect(model.previewModel == nil)
        #expect(model.selectedNodeID == nil)
    }

    @Test("Only the selected session working directory becomes a root")
    func usesSingleSessionWorkingDirectory() throws {
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let model = WorkspaceExplorerFeatureModel()

        model.configure(sessionID: "session", workingDirectoryPath: "  \(rootURL.path)  ")

        #expect(model.roots.count == 1)
        #expect(model.roots.first?.url.standardizedFileURL == rootURL.standardizedFileURL)
        #expect(model.roots.first?.displayName == rootURL.lastPathComponent)
    }

    @Test("A session without a working directory has no file tree root")
    func emptyWorkingDirectoryHasNoRoot() {
        let model = WorkspaceExplorerFeatureModel()

        model.configure(sessionID: "session", workingDirectoryPath: "  ")

        #expect(model.roots.isEmpty)
    }

    @Test("The session file tree is presented and dismissed as a floating tool")
    func presentsAndDismissesTree() throws {
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let model = WorkspaceExplorerFeatureModel()

        model.presentTree(sessionID: "session", workingDirectoryPath: rootURL.path)

        #expect(model.isTreePresented)
        #expect(model.roots.count == 1)
        #expect(model.roots.first?.url.standardizedFileURL == rootURL.standardizedFileURL)

        model.toggleTree(sessionID: "session", workingDirectoryPath: rootURL.path)

        #expect(!model.isTreePresented)

        model.toggleTree(sessionID: "session", workingDirectoryPath: rootURL.path)

        #expect(model.isTreePresented)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for workspace explorer state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-explorer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
