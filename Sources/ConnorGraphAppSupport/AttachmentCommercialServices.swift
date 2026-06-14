import Foundation
import ConnorGraphCore

public struct AppAttachmentProviderCacheStore: Sendable {
    public var paths: AppStoragePaths
    public init(paths: AppStoragePaths) { self.paths = paths }

    public func save(_ ref: AgentAttachmentRemoteFileRef, sessionID: String) throws {
        let directory = providerDirectory(sessionID: sessionID, provider: ref.provider)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try jsonEncoder(pretty: true).encode(ref)
        try data.write(to: directory.appendingPathComponent("\(ref.attachmentID).json"), options: [.atomic])
        try appendJSONLine(ref, to: attachmentsRoot(sessionID: sessionID).appendingPathComponent("purge-ledger.jsonl"))
    }

    public func load(sessionID: String, provider: AgentAttachmentProvider, attachmentID: String) throws -> AgentAttachmentRemoteFileRef {
        let url = providerDirectory(sessionID: sessionID, provider: provider).appendingPathComponent("\(attachmentID).json")
        let data = try Data(contentsOf: url)
        return try jsonDecoder().decode(AgentAttachmentRemoteFileRef.self, from: data)
    }

    private func providerDirectory(sessionID: String, provider: AgentAttachmentProvider) -> URL {
        attachmentsRoot(sessionID: sessionID).appendingPathComponent("provider-cache", isDirectory: true).appendingPathComponent(provider.rawValue, isDirectory: true)
    }

    private func attachmentsRoot(sessionID: String) -> URL { paths.sessionArtifactDirectories(sessionID: sessionID).attachments }
}

public struct AttachmentAuditLedger: Sendable {
    public var paths: AppStoragePaths
    public init(paths: AppStoragePaths) { self.paths = paths }

    public func append(_ event: AgentAttachmentAuditEvent) throws {
        let root = paths.sessionArtifactDirectories(sessionID: event.sessionID).attachments
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try appendJSONLine(event, to: root.appendingPathComponent("audit.jsonl"))
    }

    public func load(sessionID: String) throws -> [AgentAttachmentAuditEvent] {
        let url = paths.sessionArtifactDirectories(sessionID: sessionID).attachments.appendingPathComponent("audit.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try loadJSONLines(AgentAttachmentAuditEvent.self, from: url)
    }
}

public struct AttachmentEnterpriseAuditMirror: Sendable {
    public enum Mode: Sendable, Equatable { case disabled, file(URL), dryRunHTTP(URL) }
    public var mode: Mode
    public init(mode: Mode = .disabled) { self.mode = mode }

    public func mirror(_ event: AgentAttachmentAuditEvent) throws -> String {
        switch mode {
        case .disabled:
            return "disabled"
        case .dryRunHTTP(let url):
            return "dry-run:\(url.absoluteString):\(event.id)"
        case .file(let url):
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try appendJSONLine(event, to: url)
            return "mirrored:file"
        }
    }
}

public struct AppAttachmentSearchIndex: Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public var sessionID: String
        public var attachmentID: String
        public var displayName: String
        public var manifestRelativePath: String
        public var text: String
    }

    public var paths: AppStoragePaths
    public init(paths: AppStoragePaths) { self.paths = paths }

    public func index(sessionID: String, manifest: AgentAttachmentManifest, extractedText: String) throws {
        let directory = indexDirectory(sessionID: sessionID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = Entry(sessionID: sessionID, attachmentID: manifest.id, displayName: manifest.displayName, manifestRelativePath: manifest.manifestRelativePath, text: extractedText)
        try jsonEncoder(pretty: true).encode(entry).write(to: directory.appendingPathComponent("\(manifest.id).json"), options: [.atomic])
    }

    public func search(sessionID: String, query: String, limit: Int = 10) throws -> [AgentAttachmentSearchResult] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let directory = indexDirectory(sessionID: sessionID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        var results: [AgentAttachmentSearchResult] = []
        for url in urls {
            let entry = try jsonDecoder().decode(Entry.self, from: Data(contentsOf: url))
            let haystack = "\(entry.displayName)\n\(entry.text)".lowercased()
            guard haystack.contains(q) else { continue }
            let score = entry.displayName.lowercased().contains(q) ? 2.0 : 1.0
            results.append(AgentAttachmentSearchResult(attachmentID: entry.attachmentID, displayName: entry.displayName, snippet: snippet(entry.text, query: q), score: score, manifestRelativePath: entry.manifestRelativePath))
        }
        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }

    private func indexDirectory(sessionID: String) -> URL {
        paths.sessionArtifactDirectories(sessionID: sessionID).attachments.appendingPathComponent("index", isDirectory: true).appendingPathComponent("fts", isDirectory: true)
    }
}

public struct AppAttachmentEmbeddingIndex: Sendable {
    public struct EmbeddingRecord: Codable, Sendable, Equatable {
        public var attachmentID: String
        public var model: String
        public var dimension: Int
        public var vector: [Double]
    }

    public var paths: AppStoragePaths
    public init(paths: AppStoragePaths) { self.paths = paths }

    public func deterministicEmbedding(for text: String, dimension: Int = 8) -> [Double] {
        var vector = Array(repeating: 0.0, count: dimension)
        for (offset, scalar) in text.unicodeScalars.enumerated() {
            vector[offset % dimension] += Double(scalar.value % 97) / 97.0
        }
        return vector
    }

    public func index(sessionID: String, attachmentID: String, text: String, model: String = "deterministic-local", dimension: Int = 8) throws {
        let directory = paths.sessionArtifactDirectories(sessionID: sessionID).attachments.appendingPathComponent("index", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var records = try load(sessionID: sessionID).filter { $0.attachmentID != attachmentID }
        records.append(EmbeddingRecord(attachmentID: attachmentID, model: model, dimension: dimension, vector: deterministicEmbedding(for: text, dimension: dimension)))
        try jsonEncoder(pretty: true).encode(records).write(to: directory.appendingPathComponent("embedding-index.json"), options: [.atomic])
    }

    public func load(sessionID: String) throws -> [EmbeddingRecord] {
        let url = paths.sessionArtifactDirectories(sessionID: sessionID).attachments.appendingPathComponent("index", isDirectory: true).appendingPathComponent("embedding-index.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try jsonDecoder().decode([EmbeddingRecord].self, from: Data(contentsOf: url))
    }
}

public struct AttachmentGraphEvidenceAdmission: Sendable {
    public var paths: AppStoragePaths
    public init(paths: AppStoragePaths) { self.paths = paths }

    public func createCandidate(sessionID: String, messageID: String?, manifest: AgentAttachmentManifest, extractor: AgentAttachmentExtractionEngine, summary: String? = nil, now: Date = Date()) throws -> AgentAttachmentEvidenceCandidate {
        let derivatives = manifest.derivativeRefs.map(\.relativePath) + [manifest.extractedTextRelativePath].compactMap { $0 }
        let candidate = AgentAttachmentEvidenceCandidate(
            sessionID: sessionID,
            messageID: messageID,
            attachmentID: manifest.id,
            displayName: manifest.displayName,
            sha256: manifest.sha256,
            manifestRelativePath: manifest.manifestRelativePath,
            derivativeRelativePaths: Array(Set(derivatives)).sorted(),
            extractor: extractor,
            summary: summary ?? manifest.previewText ?? manifest.displayName,
            createdAt: now
        )
        let root = paths.sessionArtifactDirectories(sessionID: sessionID).attachments
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try appendJSONLine(candidate, to: root.appendingPathComponent("evidence-candidates.jsonl"))
        return candidate
    }

    public func loadCandidates(sessionID: String) throws -> [AgentAttachmentEvidenceCandidate] {
        let url = paths.sessionArtifactDirectories(sessionID: sessionID).attachments.appendingPathComponent("evidence-candidates.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try loadJSONLines(AgentAttachmentEvidenceCandidate.self, from: url)
    }
}

private func jsonEncoder(pretty: Bool = false) -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
    return encoder
}

private func jsonDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private func appendJSONLine<T: Encodable>(_ value: T, to url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: jsonEncoder().encode(value))
    try handle.write(contentsOf: Data("\n".utf8))
}

private func loadJSONLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
    let text = try String(contentsOf: url, encoding: .utf8)
    return try text.split(separator: "\n").map { try jsonDecoder().decode(T.self, from: Data($0.utf8)) }
}

private func snippet(_ text: String, query: String, radius: Int = 80) -> String {
    let lower = text.lowercased()
    guard let range = lower.range(of: query) else { return String(text.prefix(radius * 2)) }
    let start = text.distance(from: text.startIndex, to: range.lowerBound)
    let lowerBound = max(0, start - radius)
    let upperBound = min(text.count, start + query.count + radius)
    let s = text.index(text.startIndex, offsetBy: lowerBound)
    let e = text.index(text.startIndex, offsetBy: upperBound)
    return String(text[s..<e])
}
