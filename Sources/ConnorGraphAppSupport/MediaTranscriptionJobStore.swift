import Foundation
import ConnorGraphCore

public struct MediaTranscriptionJobEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var jobID: String
    public var state: MediaTranscriptionJobState
    public var message: String
    public var createdAt: Date
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, jobID: String, state: MediaTranscriptionJobState, message: String, createdAt: Date = Date(), metadata: [String: String] = [:]) {
        self.id = id
        self.jobID = jobID
        self.state = state
        self.message = message
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public struct MediaTranscriptionDiagnostics: Codable, Sendable, Equatable {
    public var jobID: String
    public var lastUpdatedAt: Date
    public var runtimeSnapshot: MediaRuntimeSnapshot?
    public var entries: [String]

    public init(jobID: String, lastUpdatedAt: Date = Date(), runtimeSnapshot: MediaRuntimeSnapshot? = nil, entries: [String] = []) {
        self.jobID = jobID
        self.lastUpdatedAt = lastUpdatedAt
        self.runtimeSnapshot = runtimeSnapshot
        self.entries = entries
    }
}

public enum MediaTranscriptionJobStoreError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingJob(String)
    case invalidOwnerSession(String)

    public var description: String {
        switch self {
        case .missingJob(let id): "missingJob: \(id)"
        case .invalidOwnerSession(let id): "invalidOwnerSession: \(id)"
        }
    }
}

public struct MediaTranscriptionJobStore: Sendable {
    public var paths: AppStoragePaths

    public init(paths: AppStoragePaths) {
        self.paths = paths
    }

    public func jobDirectory(sessionID: String, jobID: String) -> URL {
        paths.sessionArtifactDirectories(sessionID: sessionID)
            .data
            .appendingPathComponent("media-jobs", isDirectory: true)
            .appendingPathComponent(jobID, isDirectory: true)
    }

    public func save(_ job: BrowserMediaTranscriptionJob) throws {
        guard !job.ownerSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MediaTranscriptionJobStoreError.invalidOwnerSession(job.id)
        }
        let directory = jobDirectory(sessionID: job.ownerSessionID, jobID: job.id)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try encode(job).write(to: directory.appendingPathComponent("job.json"), options: [.atomic])
        try encode(job.progress).write(to: directory.appendingPathComponent("progress.json"), options: [.atomic])
    }

    public func load(sessionID: String, jobID: String) throws -> BrowserMediaTranscriptionJob {
        let url = jobDirectory(sessionID: sessionID, jobID: jobID).appendingPathComponent("job.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw MediaTranscriptionJobStoreError.missingJob(jobID) }
        return try decode(BrowserMediaTranscriptionJob.self, from: url)
    }

    public func appendEvent(_ event: MediaTranscriptionJobEvent, sessionID: String) throws {
        let directory = jobDirectory(sessionID: sessionID, jobID: event.jobID)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("events.jsonl")
        if !fileManager.fileExists(atPath: url.path) { fileManager.createFile(atPath: url.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: encodeLine(event))
        try handle.write(contentsOf: Data("\n".utf8))
    }

    public func loadEvents(sessionID: String, jobID: String) throws -> [MediaTranscriptionJobEvent] {
        let url = jobDirectory(sessionID: sessionID, jobID: jobID).appendingPathComponent("events.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try text.split(separator: "\n").map { line in
            try decoder.decode(MediaTranscriptionJobEvent.self, from: Data(line.utf8))
        }
    }

    public func updateProgress(_ progress: MediaTranscriptionProgress, sessionID: String, jobID: String) throws {
        let directory = jobDirectory(sessionID: sessionID, jobID: jobID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encode(progress).write(to: directory.appendingPathComponent("progress.json"), options: [.atomic])
    }

    public func saveDiagnostics(_ diagnostics: MediaTranscriptionDiagnostics, sessionID: String) throws {
        let directory = jobDirectory(sessionID: sessionID, jobID: diagnostics.jobID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encode(diagnostics).write(to: directory.appendingPathComponent("diagnostics.json"), options: [.atomic])
    }

    public func markCheckpoint(_ name: String, sessionID: String, jobID: String, at date: Date = Date()) throws {
        let checkpoints = jobDirectory(sessionID: sessionID, jobID: jobID).appendingPathComponent("checkpoints", isDirectory: true)
        try FileManager.default.createDirectory(at: checkpoints, withIntermediateDirectories: true)
        let safeName = AppSessionAttachmentStore.sanitizedFilename(name)
        let payload = ["checkpoint": safeName, "createdAt": ISO8601DateFormatter().string(from: date)]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: checkpoints.appendingPathComponent("\(safeName).checkpoint.json"), options: [.atomic])
    }

    public func hasCheckpoint(_ name: String, sessionID: String, jobID: String) -> Bool {
        let safeName = AppSessionAttachmentStore.sanitizedFilename(name)
        return FileManager.default.fileExists(atPath: jobDirectory(sessionID: sessionID, jobID: jobID)
            .appendingPathComponent("checkpoints", isDirectory: true)
            .appendingPathComponent("\(safeName).checkpoint.json").path)
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
