import Foundation
import ConnorGraphCore

public enum AppSessionCapsuleRepositoryError: Error, Equatable, CustomStringConvertible {
    case invalidRecordSessionID(expected: String, actual: String)

    public var description: String {
        switch self {
        case .invalidRecordSessionID(let expected, let actual):
            "invalidRecordSessionID: expected \(expected), actual \(actual)"
        }
    }
}

public struct AppSessionCapsuleRepository: @unchecked Sendable {
    public var storagePaths: AppStoragePaths
    public var fileManager: FileManager

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default) {
        self.storagePaths = storagePaths
        self.fileManager = fileManager
    }

    public func directories(sessionID: String) throws -> AgentSessionArtifactDirectories {
        try storagePaths.ensureSessionArtifactDirectories(sessionID: sessionID, fileManager: fileManager)
    }

    public func manifestURL(sessionID: String) throws -> URL {
        let directories = try directories(sessionID: sessionID)
        return directories.root.appendingPathComponent("manifest.json")
    }

    public func sessionStateURL(sessionID: String) throws -> URL {
        let directories = try directories(sessionID: sessionID)
        return directories.state.appendingPathComponent("session-state.json")
    }

    public func recordsURL(sessionID: String) throws -> URL {
        let directories = try directories(sessionID: sessionID)
        return directories.state.appendingPathComponent("records.jsonl")
    }

    public func browserStateURL(sessionID: String) throws -> URL {
        let directories = try directories(sessionID: sessionID)
        return directories.browser.appendingPathComponent("browser-state.json")
    }

    public func loadManifest(sessionID: String) throws -> AppSessionManifest? {
        try loadJSON(AppSessionManifest.self, from: manifestURL(sessionID: sessionID))
    }

    public func saveManifest(_ manifest: AppSessionManifest, sessionID: String) throws {
        try saveJSON(manifest, to: manifestURL(sessionID: sessionID))
    }

    public func loadState(sessionID: String) throws -> AppSessionStateSnapshot? {
        try loadJSON(AppSessionStateSnapshot.self, from: sessionStateURL(sessionID: sessionID))
    }

    public func saveState(_ state: AppSessionStateSnapshot, sessionID: String) throws {
        try saveJSON(state, to: sessionStateURL(sessionID: sessionID))
        try upsertManifest(sessionID: sessionID) { manifest in
            manifest.stateFile = "state/session-state.json"
            manifest.updatedAt = state.updatedAt
            manifest.workspace = state.workspace ?? manifest.workspace
            manifest.recordSummary = state.recordSummary ?? manifest.recordSummary
            manifest.attachmentSummary = state.attachmentSummary ?? manifest.attachmentSummary
        }
    }

    public func loadBrowserState(sessionID: String) throws -> AppBrowserStateSnapshot? {
        try loadJSON(AppBrowserStateSnapshot.self, from: browserStateURL(sessionID: sessionID))
    }

    public func saveBrowserState(_ state: AppBrowserStateSnapshot, sessionID: String) throws {
        try saveJSON(state, to: browserStateURL(sessionID: sessionID))
        try upsertManifest(sessionID: sessionID) { manifest in
            manifest.browserStateFile = "browser/browser-state.json"
            manifest.updatedAt = state.updatedAt
        }

        var sessionState = try loadState(sessionID: sessionID) ?? AppSessionStateSnapshot(sessionID: sessionID)
        sessionState.updatedAt = state.updatedAt
        sessionState.browser = AppBrowserStateReference(
            path: "browser/browser-state.json",
            tabCount: state.tabs.count,
            threadCount: state.threads.count,
            updatedAt: state.updatedAt
        )
        try saveState(sessionState, sessionID: sessionID)
    }

    public func appendRecord(_ record: AppSessionRecord, sessionID: String) throws {
        guard record.sessionID == sessionID else {
            throw AppSessionCapsuleRepositoryError.invalidRecordSessionID(expected: sessionID, actual: record.sessionID)
        }
        let url = try recordsURL(sessionID: sessionID)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = try lineEncoder().encode(record)
        guard var payload = String(data: line, encoding: .utf8) else { return }
        payload.append("\n")
        let data = Data(payload.utf8)
        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: [.atomic])
        }
        let records = try loadRecords(sessionID: sessionID, limit: nil)
        let summary = AppSessionRecordSummary(count: records.count, updatedAt: record.createdAt)
        try upsertManifest(sessionID: sessionID) { manifest in
            manifest.recordsFile = "state/records.jsonl"
            manifest.recordSummary = summary
            manifest.updatedAt = record.createdAt
        }
        var state = try loadState(sessionID: sessionID) ?? AppSessionStateSnapshot(sessionID: sessionID)
        state.updatedAt = record.createdAt
        state.recordSummary = summary
        try saveState(state, sessionID: sessionID)
    }

    public func loadRecords(sessionID: String, limit: Int? = nil) throws -> [AppSessionRecord] {
        let url = try recordsURL(sessionID: sessionID)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = decoder()
        var records: [AppSessionRecord] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8) else { continue }
            guard let record = try? decoder.decode(AppSessionRecord.self, from: lineData) else { continue }
            records.append(record)
        }
        if let limit, records.count > limit {
            return Array(records.suffix(limit))
        }
        return records
    }

    public func attachmentSummary(sessionID: String) throws -> AppSessionAttachmentSummary {
        let directories = try directories(sessionID: sessionID)
        guard let enumerator = fileManager.enumerator(at: directories.attachments, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) else {
            return AppSessionAttachmentSummary()
        }
        var count = 0
        var totalBytes: Int64 = 0
        var latest: Date?
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }
            count += 1
            totalBytes += Int64(values.fileSize ?? 0)
            if let modified = values.contentModificationDate, latest == nil || modified > latest! {
                latest = modified
            }
        }
        return AppSessionAttachmentSummary(count: count, totalBytes: totalBytes, updatedAt: latest)
    }

    public func refreshManifest(sessionID: String) throws -> AppSessionManifest {
        let records = try loadRecords(sessionID: sessionID, limit: nil)
        let attachments = try attachmentSummary(sessionID: sessionID)
        let browser = try loadBrowserState(sessionID: sessionID)
        let now = Date()
        let manifest = AppSessionManifest(
            sessionID: sessionID,
            updatedAt: now,
            stateFile: fileManager.fileExists(atPath: (try sessionStateURL(sessionID: sessionID)).path) ? "state/session-state.json" : nil,
            recordsFile: fileManager.fileExists(atPath: (try recordsURL(sessionID: sessionID)).path) ? "state/records.jsonl" : nil,
            browserStateFile: browser == nil ? nil : "browser/browser-state.json",
            workspace: (try loadState(sessionID: sessionID))?.workspace,
            attachmentSummary: attachments,
            recordSummary: AppSessionRecordSummary(count: records.count, updatedAt: records.last?.createdAt)
        )
        try saveManifest(manifest, sessionID: sessionID)
        return manifest
    }

    private func upsertManifest(sessionID: String, mutate: (inout AppSessionManifest) -> Void) throws {
        var manifest = try loadManifest(sessionID: sessionID) ?? AppSessionManifest(sessionID: sessionID)
        mutate(&manifest)
        try saveManifest(manifest, sessionID: sessionID)
    }

    private func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder().decode(type, from: data)
    }

    private func saveJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder().encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func lineEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
