import CryptoKit
import Foundation
import ConnorGraphCore

public protocol AttachmentExtractorService: Sendable {
    func extract(_ request: AttachmentExtractionRequest) async throws -> AttachmentExtractionResult
}

extension AttachmentExtractionOrchestrator: AttachmentExtractorService {}

public struct AttachmentExtractionJobStore: Sendable {
    public var paths: AppStoragePaths

    public init(paths: AppStoragePaths) {
        self.paths = paths
    }

    public func append(_ job: AgentAttachmentExtractionJob) throws {
        let url = try jobsURL(sessionID: job.sessionID)
        try appendJSONLine(job, to: url)
    }

    public func load(sessionID: String) throws -> [AgentAttachmentExtractionJob] {
        let url = paths.sessionArtifactDirectories(sessionID: sessionID).attachments.appendingPathComponent("extraction-jobs.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try loadJSONLines(AgentAttachmentExtractionJob.self, from: url)
    }

    public func latestJobs(sessionID: String) throws -> [AgentAttachmentExtractionJob] {
        var byID: [String: AgentAttachmentExtractionJob] = [:]
        for job in try load(sessionID: sessionID) {
            byID[job.id] = job
        }
        return byID.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func appendStatus(_ job: AgentAttachmentExtractionJob, status: AgentAttachmentExtractionJobStatus, now: Date = Date(), lastError: String? = nil) throws -> AgentAttachmentExtractionJob {
        var updated = job
        updated.status = status
        if status == .running { updated.startedAt = now }
        if [.succeeded, .unsupported, .failed, .cancelled].contains(status) { updated.completedAt = now }
        if let lastError { updated.lastError = lastError }
        try append(updated)
        return updated
    }

    public func recoverInterruptedJobs(sessionID: String, now: Date = Date()) throws -> [AgentAttachmentExtractionJob] {
        let interrupted = try latestJobs(sessionID: sessionID).filter { $0.status == .running || $0.status == .queued }
        var recovered: [AgentAttachmentExtractionJob] = []
        for job in interrupted {
            var next = job
            next.status = .queued
            next.startedAt = nil
            next.completedAt = nil
            next.lastError = "Extraction was interrupted and re-queued at \(now)."
            try append(next)
            recovered.append(next)
        }
        return recovered
    }

    private func jobsURL(sessionID: String) throws -> URL {
        let root = paths.sessionArtifactDirectories(sessionID: sessionID).attachments
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("extraction-jobs.jsonl")
    }
}

public struct AttachmentDerivativeWriter: Sendable {
    public var paths: AppStoragePaths

    public init(paths: AppStoragePaths) {
        self.paths = paths
    }

    public func writeExtractedMarkdown(
        _ markdown: String,
        sessionID: String,
        attachmentID: String,
        runID: String,
        now: Date = Date()
    ) throws -> (currentPath: String, runPath: String, refs: [AgentAttachmentDerivativeRef]) {
        let directories = try paths.ensureSessionArtifactDirectories(sessionID: sessionID)
        let derivativesDirectory = directories.attachments
            .appendingPathComponent(attachmentID, isDirectory: true)
            .appendingPathComponent("derivatives", isDirectory: true)
        let currentDirectory = derivativesDirectory.appendingPathComponent("current", isDirectory: true)
        let runDirectory = derivativesDirectory
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let currentURL = currentDirectory.appendingPathComponent("extracted.md")
        let runURL = runDirectory.appendingPathComponent("extracted.md")
        try markdown.write(to: currentURL, atomically: true, encoding: .utf8)
        try markdown.write(to: runURL, atomically: true, encoding: .utf8)

        let data = Data(markdown.utf8)
        let digest = sha256Hex(data)
        let currentPath = "attachments/\(attachmentID)/derivatives/current/extracted.md"
        let runPath = "attachments/\(attachmentID)/derivatives/runs/\(runID)/extracted.md"
        let refs = [
            AgentAttachmentDerivativeRef(kind: .extractedMarkdown, relativePath: currentPath, byteCount: Int64(data.count), sha256: digest, createdAt: now),
            AgentAttachmentDerivativeRef(kind: .extractedMarkdown, relativePath: runPath, byteCount: Int64(data.count), sha256: digest, createdAt: now)
        ]
        return (currentPath, runPath, refs)
    }
}

public struct AttachmentManifestUpdater: Sendable {
    public var paths: AppStoragePaths

    public init(paths: AppStoragePaths) {
        self.paths = paths
    }

    public func update(
        sessionID: String,
        attachmentID: String,
        extractionStatus: AgentAttachmentExtractionStatus,
        extractedTextRelativePath: String?,
        previewText: String?,
        derivativeRefs: [AgentAttachmentDerivativeRef],
        extractionReport: AgentAttachmentExtractionReport,
        now: Date = Date()
    ) throws -> AgentAttachmentManifest {
        var manifest = try AppSessionAttachmentStore(paths: paths).loadManifest(sessionID: sessionID, attachmentID: attachmentID)
        manifest.extractionStatus = extractionStatus
        manifest.extractedTextRelativePath = extractedTextRelativePath
        manifest.previewText = previewText ?? manifest.previewText
        manifest.derivativeRefs = mergeDerivativeRefs(existing: manifest.derivativeRefs, new: derivativeRefs)
        manifest.extractionReports.append(extractionReport)
        manifest.updatedAt = now
        try write(manifest, sessionID: sessionID)
        return manifest
    }

    public func write(_ manifest: AgentAttachmentManifest, sessionID: String) throws {
        let url = paths.sessionArtifactDirectories(sessionID: sessionID)
            .attachments
            .appendingPathComponent(manifest.id, isDirectory: true)
            .appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        let tmp = url.deletingLastPathComponent().appendingPathComponent("manifest.json.tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.moveItem(at: tmp, to: url)
    }

    private func mergeDerivativeRefs(existing: [AgentAttachmentDerivativeRef], new: [AgentAttachmentDerivativeRef]) -> [AgentAttachmentDerivativeRef] {
        var byPath: [String: AgentAttachmentDerivativeRef] = [:]
        for ref in existing { byPath[ref.relativePath] = ref }
        for ref in new { byPath[ref.relativePath] = ref }
        return byPath.values.sorted { $0.relativePath < $1.relativePath }
    }
}

public struct AttachmentExtractionJobProcessor: Sendable {
    public var paths: AppStoragePaths
    public var extractor: any AttachmentExtractorService
    public var derivativeWriter: AttachmentDerivativeWriter
    public var manifestUpdater: AttachmentManifestUpdater

    public init(paths: AppStoragePaths, extractor: any AttachmentExtractorService = AttachmentExtractionOrchestrator()) {
        self.paths = paths
        self.extractor = extractor
        self.derivativeWriter = AttachmentDerivativeWriter(paths: paths)
        self.manifestUpdater = AttachmentManifestUpdater(paths: paths)
    }

    public func process(_ job: AgentAttachmentExtractionJob) async throws -> AgentAttachmentExtractionJob {
        let started = Date()
        let store = AppSessionAttachmentStore(paths: paths)
        let manifest = try store.loadManifest(sessionID: job.sessionID, attachmentID: job.attachmentID)
        let originalURL = paths.sessionArtifactDirectories(sessionID: job.sessionID).root.appendingPathComponent(manifest.storedRelativePath)
        let derivativesDirectory = paths.sessionArtifactDirectories(sessionID: job.sessionID).attachments
            .appendingPathComponent(manifest.id, isDirectory: true)
            .appendingPathComponent("derivatives", isDirectory: true)
        let request = AttachmentExtractionRequest(
            sessionID: job.sessionID,
            manifest: manifest,
            originalFileURL: originalURL,
            derivativesDirectoryURL: derivativesDirectory,
            requestedCapabilities: job.requestedCapabilities
        )
        let result = try await extractor.extract(request)
        var report = result.report
        var derivativeRefs: [AgentAttachmentDerivativeRef] = []
        var extractedPath: String?
        if let markdown = result.extractedMarkdown, result.report.status == .extracted {
            let runID = AppSessionAttachmentStore.derivativeRunID(now: started, engine: result.report.engine)
            let written = try derivativeWriter.writeExtractedMarkdown(markdown, sessionID: job.sessionID, attachmentID: manifest.id, runID: runID, now: Date())
            extractedPath = written.currentPath
            derivativeRefs = written.refs
            report.derivativeRefs = mergeDerivativeRefs(existing: report.derivativeRefs, new: derivativeRefs)
        }
        _ = try manifestUpdater.update(
            sessionID: job.sessionID,
            attachmentID: job.attachmentID,
            extractionStatus: report.status,
            extractedTextRelativePath: extractedPath,
            previewText: result.previewText,
            derivativeRefs: derivativeRefs,
            extractionReport: report,
            now: Date()
        )
        var completed = job
        completed.status = Self.jobStatus(for: report.status)
        completed.completedAt = Date()
        completed.lastError = report.errors.first
        return completed
    }

    private static func jobStatus(for extractionStatus: AgentAttachmentExtractionStatus) -> AgentAttachmentExtractionJobStatus {
        switch extractionStatus {
        case .extracted: return .succeeded
        case .unsupported, .skippedOversize: return .unsupported
        case .failed: return .failed
        case .pending: return .queued
        }
    }

    private func mergeDerivativeRefs(existing: [AgentAttachmentDerivativeRef], new: [AgentAttachmentDerivativeRef]) -> [AgentAttachmentDerivativeRef] {
        var byPath: [String: AgentAttachmentDerivativeRef] = [:]
        for ref in existing { byPath[ref.relativePath] = ref }
        for ref in new { byPath[ref.relativePath] = ref }
        return byPath.values.sorted { $0.relativePath < $1.relativePath }
    }
}

public actor AttachmentExtractionQueue {
    private var queued: [AgentAttachmentExtractionJob] = []
    private let jobStore: AttachmentExtractionJobStore
    private let processor: AttachmentExtractionJobProcessor

    public init(jobStore: AttachmentExtractionJobStore, processor: AttachmentExtractionJobProcessor) {
        self.jobStore = jobStore
        self.processor = processor
    }

    public func enqueue(sessionID: String, attachmentID: String, requestedCapabilities: [String] = [], now: Date = Date()) throws -> AgentAttachmentExtractionJob {
        let job = AgentAttachmentExtractionJob(sessionID: sessionID, attachmentID: attachmentID, requestedCapabilities: requestedCapabilities, createdAt: now)
        try jobStore.append(job)
        queued.append(job)
        return job
    }

    public func drain(sessionID: String) async throws {
        let pending = try jobStore.latestJobs(sessionID: sessionID).filter { $0.status == .queued }
        let jobs = (queued + pending).uniquedByID()
        queued.removeAll()
        for job in jobs where job.sessionID == sessionID {
            let running = try jobStore.appendStatus(job, status: .running)
            do {
                let completed = try await processor.process(running)
                try jobStore.append(completed)
            } catch {
                _ = try jobStore.appendStatus(running, status: .failed, lastError: error.localizedDescription)
            }
        }
    }
}

private extension Array where Element == AgentAttachmentExtractionJob {
    func uniquedByID() -> [AgentAttachmentExtractionJob] {
        var seen: Set<String> = []
        var result: [AgentAttachmentExtractionJob] = []
        for job in self where !seen.contains(job.id) {
            seen.insert(job.id)
            result.append(job)
        }
        return result
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

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
