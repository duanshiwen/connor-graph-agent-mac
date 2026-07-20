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
        let draft = WorkspaceRootDraft(displayName: "Project", path: rootURL.path, isPrimary: true)
        model.configure(sessionID: "session", roots: [draft])

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
        let draft = WorkspaceRootDraft(displayName: "Project", path: rootURL.path, isPrimary: true)
        model.configure(sessionID: "first", roots: [draft])
        let root = try #require(model.roots.first)
        model.toggleRoot(root)

        model.configure(sessionID: "second", roots: [draft])

        #expect(model.expandedNodeIDs.isEmpty)
        #expect(model.childrenByNodeID.isEmpty)
        #expect(model.selectedNodeID == nil)
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
