import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Workspace Directory Loader")
struct WorkspaceDirectoryLoaderTests {
    @Test("Parses added and modified Git files")
    func parsesGitStatuses() {
        let root = URL(fileURLWithPath: "/tmp/workspace-git-status", isDirectory: true)
        let data = Data("?? New.swift\0 M Changed.swift\0A  Staged.swift\0".utf8)

        let statuses = WorkspaceGitStatusLoader.parsePorcelainV1Z(data, repositoryRootURL: root)

        #expect(statuses[root.appendingPathComponent("New.swift").path] == .added)
        #expect(statuses[root.appendingPathComponent("Changed.swift").path] == .modified)
        #expect(statuses[root.appendingPathComponent("Staged.swift").path] == .added)
    }

    @Test("Loads only direct children with stable ordering")
    func loadsDirectChildren() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "nested".write(to: nested.appendingPathComponent("Nested.swift"), atomically: true, encoding: .utf8)
        try "readme".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "hidden".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        let nodes = try await WorkspaceDirectoryLoader().children(rootID: "root", rootURL: root, directoryURL: root)

        #expect(nodes.map(\.name) == ["Sources", ".env", "README.md"])
        #expect(nodes.first?.kind == .directory)
        #expect(nodes.contains { $0.relativePath == "Sources/Nested.swift" } == false)
        #expect(nodes.first { $0.name == ".env" }?.isHidden == true)
        #expect(Set(nodes.map(\.id)).count == nodes.count)
    }

    @Test("Cache is reused until an explicit refresh")
    func refreshesExplicitly() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let loader = WorkspaceDirectoryLoader()

        #expect(try await loader.children(rootID: "root", rootURL: root, directoryURL: root).isEmpty)
        try "new".write(to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        #expect(try await loader.children(rootID: "root", rootURL: root, directoryURL: root).isEmpty)
        let refreshed = try await loader.children(rootID: "root", rootURL: root, directoryURL: root, forceRefresh: true)
        #expect(refreshed.map(\.name) == ["new.txt"])
    }

    @Test("Rejects directories outside the workspace root")
    func rejectsOutsideDirectory() async throws {
        let root = try temporaryDirectory()
        let outside = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        await #expect(throws: WorkspaceDirectoryLoaderError.self) {
            try await WorkspaceDirectoryLoader().children(rootID: "root", rootURL: root, directoryURL: outside)
        }
    }

    @Test("Symbolic links are visible but not expandable")
    func doesNotTraverseSymbolicLinks() async throws {
        let root = try temporaryDirectory()
        let outside = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let link = root.appendingPathComponent("external")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let node = try #require(await WorkspaceDirectoryLoader().children(rootID: "root", rootURL: root, directoryURL: root).first)

        #expect(node.kind == .symbolicLink)
        #expect(node.isExpandable == false)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-tree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
