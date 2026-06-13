import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore

private func makeTempWorkspace(_ name: String = UUID().uuidString) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("connor-local-policy-tests-")
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func localWorkspacePolicyAllowsRelativePathsInsideWorkspace() throws {
    let workspace = try makeTempWorkspace()
    let file = workspace.appendingPathComponent("Sources/App.swift")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "hello".write(to: file, atomically: true, encoding: .utf8)
    let policy = LocalWorkspacePolicy(workingDirectory: workspace)

    let resolved = try policy.resolvePath("Sources/App.swift")

    #expect(resolved.path == file.standardizedFileURL.resolvingSymlinksInPath().path)
    try policy.validateReadablePath(resolved)
}

@Test func localWorkspacePolicyRejectsPathsOutsideWorkspace() throws {
    let workspace = try makeTempWorkspace()
    let outside = FileManager.default.temporaryDirectory.appendingPathComponent("connor-outside-").appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "secret".write(to: outside, atomically: true, encoding: .utf8)
    let policy = LocalWorkspacePolicy(workingDirectory: workspace)

    #expect(throws: LocalWorkspacePolicyError.self) {
        _ = try policy.resolvePath(outside.path)
    }
}

@Test func localWorkspacePolicyRejectsSymlinkEscapes() throws {
    let workspace = try makeTempWorkspace()
    let outsideDirectory = try makeTempWorkspace("outside-" + UUID().uuidString)
    let outsideFile = outsideDirectory.appendingPathComponent("secret.txt")
    try "secret".write(to: outsideFile, atomically: true, encoding: .utf8)
    let link = workspace.appendingPathComponent("linked-secret.txt")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideFile)
    let policy = LocalWorkspacePolicy(workingDirectory: workspace)

    #expect(throws: LocalWorkspacePolicyError.self) {
        _ = try policy.resolvePath("linked-secret.txt")
    }
}

@Test func localWorkspacePolicyRejectsProtectedWorkspaceWrites() throws {
    let workspace = try makeTempWorkspace()
    let gitObjects = workspace.appendingPathComponent(".git/objects/aa")
    try FileManager.default.createDirectory(at: gitObjects.deletingLastPathComponent(), withIntermediateDirectories: true)
    let envFile = workspace.appendingPathComponent(".env")
    let policy = LocalWorkspacePolicy(workingDirectory: workspace)

    #expect(throws: LocalWorkspacePolicyError.self) {
        try policy.validateWritablePath(gitObjects, operation: .createFile)
    }
    #expect(throws: LocalWorkspacePolicyError.self) {
        try policy.validateWritablePath(envFile, operation: .overwriteFile)
    }
}

@Test func localWorkspacePolicyAllowsAdditionalDirectory() throws {
    let workspace = try makeTempWorkspace()
    let additional = try makeTempWorkspace("allowed-" + UUID().uuidString)
    let file = additional.appendingPathComponent("notes.txt")
    try "ok".write(to: file, atomically: true, encoding: .utf8)
    let policy = LocalWorkspacePolicy(workingDirectory: workspace, additionalAllowedDirectories: [additional])

    let resolved = try policy.resolvePath(file.path)

    #expect(resolved.path == file.standardizedFileURL.resolvingSymlinksInPath().path)
}
