import Foundation
import ConnorGraphCore

public struct AppSessionArtifactWriteResult: Sendable, Equatable {
    public var url: URL
    public var directories: AgentSessionArtifactDirectories
    public var event: AgentSessionArtifactEvent

    public init(url: URL, directories: AgentSessionArtifactDirectories, event: AgentSessionArtifactEvent) {
        self.url = url
        self.directories = directories
        self.event = event
    }
}

public struct AppSessionArtifactManager: @unchecked Sendable {
    public var storagePaths: AppStoragePaths
    public var fileManager: FileManager

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default) {
        self.storagePaths = storagePaths
        self.fileManager = fileManager
    }

    @discardableResult
    public func writeTextArtifact(
        sessionID: String,
        kind: String,
        filename: String,
        contents: String,
        encoding: String.Encoding = .utf8,
        runID: String? = nil,
        message: String? = nil
    ) throws -> AppSessionArtifactWriteResult {
        let directories = try storagePaths.ensureSessionArtifactDirectories(sessionID: sessionID, fileManager: fileManager)
        let directory = directory(for: kind, in: directories)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeFilename = sanitizedFilename(filename)
        let url = directory.appendingPathComponent(safeFilename, isDirectory: false)
        try contents.write(to: url, atomically: true, encoding: encoding)
        let event = AgentSessionArtifactEvent(
            runID: runID,
            sessionID: sessionID,
            artifactKind: kind,
            path: url.path,
            message: message ?? "Created \(kind) artifact: \(safeFilename)"
        )
        return AppSessionArtifactWriteResult(url: url, directories: directories, event: event)
    }

    private func directory(for kind: String, in directories: AgentSessionArtifactDirectories) -> URL {
        switch kind.lowercased() {
        case "plan", "plans": directories.plans
        case "data", "dataset", "table": directories.data
        case "attachment", "attachments": directories.attachments
        case "export", "exports": directories.exports
        case "log", "logs": directories.logs
        default: directories.root.appendingPathComponent(sanitizedFilename(kind), isDirectory: true)
        }
    }

    private func sanitizedFilename(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? UUID().uuidString : trimmed
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return fallback.components(separatedBy: invalid).joined(separator: "-")
    }
}
