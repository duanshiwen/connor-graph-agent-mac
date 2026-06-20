import Foundation
import CryptoKit
import ConnorGraphCore

public struct MediaTranscriptionAttachmentPayload: Sendable, Equatable {
    public var transcriptMarkdown: String
    public var transcriptText: String?
    public var segmentsJSONL: String?
    public var diagnosticsJSON: String?
    public var displayName: String

    public init(
        transcriptMarkdown: String,
        transcriptText: String? = nil,
        segmentsJSONL: String? = nil,
        diagnosticsJSON: String? = nil,
        displayName: String = "media-transcript.md"
    ) {
        self.transcriptMarkdown = transcriptMarkdown
        self.transcriptText = transcriptText
        self.segmentsJSONL = segmentsJSONL
        self.diagnosticsJSON = diagnosticsJSON
        self.displayName = displayName
    }
}

public struct MediaTranscriptionAttachmentWriteResult: Sendable, Equatable {
    public var attachmentID: String
    public var manifest: AgentAttachmentManifest
    public var derivativeRefs: [AgentAttachmentDerivativeRef]

    public init(attachmentID: String, manifest: AgentAttachmentManifest, derivativeRefs: [AgentAttachmentDerivativeRef]) {
        self.attachmentID = attachmentID
        self.manifest = manifest
        self.derivativeRefs = derivativeRefs
    }
}

public struct MediaTranscriptionAttachmentWriter: Sendable {
    public var paths: AppStoragePaths

    public init(paths: AppStoragePaths) {
        self.paths = paths
    }

    public func write(job: BrowserMediaTranscriptionJob, payload: MediaTranscriptionAttachmentPayload, now: Date = Date()) throws -> MediaTranscriptionAttachmentWriteResult {
        let fileManager = FileManager.default
        let attachmentID = UUID().uuidString
        let runID = AppSessionAttachmentStore.derivativeRunID(now: now, engine: .manual)
        let directories = try paths.ensureSessionArtifactDirectories(sessionID: job.ownerSessionID, fileManager: fileManager)
        let attachmentDirectory = directories.attachments.appendingPathComponent(attachmentID, isDirectory: true)
        let originalDirectory = attachmentDirectory.appendingPathComponent("original", isDirectory: true)
        let currentDerivativesDirectory = attachmentDirectory.appendingPathComponent("derivatives/current", isDirectory: true)
        let runDerivativesDirectory = attachmentDirectory.appendingPathComponent("derivatives/runs", isDirectory: true).appendingPathComponent(runID, isDirectory: true)
        try fileManager.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: currentDerivativesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runDerivativesDirectory, withIntermediateDirectories: true)

        let normalizedFilename = AppSessionAttachmentStore.sanitizedFilename(payload.displayName)
        let originalURL = originalDirectory.appendingPathComponent(normalizedFilename)
        try payload.transcriptMarkdown.write(to: originalURL, atomically: true, encoding: .utf8)

        var derivativeRefs: [AgentAttachmentDerivativeRef] = []
        try writeDerivative(
            contents: payload.transcriptMarkdown,
            filename: "transcript.md",
            kind: .mediaTranscript,
            attachmentID: attachmentID,
            currentDirectory: currentDerivativesDirectory,
            runDirectory: runDerivativesDirectory,
            runID: runID,
            now: now,
            refs: &derivativeRefs
        )
        if let transcriptText = payload.transcriptText {
            try writeDerivative(contents: transcriptText, filename: "transcript.txt", kind: .mediaTranscript, attachmentID: attachmentID, currentDirectory: currentDerivativesDirectory, runDirectory: runDerivativesDirectory, runID: runID, now: now, refs: &derivativeRefs)
        }
        if let segmentsJSONL = payload.segmentsJSONL {
            try writeDerivative(contents: segmentsJSONL, filename: "segments.jsonl", kind: .pagesJSONL, attachmentID: attachmentID, currentDirectory: currentDerivativesDirectory, runDirectory: runDerivativesDirectory, runID: runID, now: now, refs: &derivativeRefs)
        }
        if let diagnosticsJSON = payload.diagnosticsJSON {
            try writeDerivative(contents: diagnosticsJSON, filename: "diagnostics.json", kind: .extractionReport, attachmentID: attachmentID, currentDirectory: currentDerivativesDirectory, runDirectory: runDerivativesDirectory, runID: runID, now: now, refs: &derivativeRefs)
        }

        let originalData = Data(payload.transcriptMarkdown.utf8)
        let manifest = AgentAttachmentManifest(
            id: attachmentID,
            displayName: payload.displayName,
            originalFilename: payload.displayName,
            normalizedFilename: normalizedFilename,
            kind: .markdown,
            mimeType: "text/markdown",
            fileExtension: "md",
            byteCount: Int64(originalData.count),
            sha256: sha256Hex(originalData),
            lifecycleStatus: .ready,
            extractionStatus: .extracted,
            storedRelativePath: "attachments/\(attachmentID)/original/\(normalizedFilename)",
            manifestRelativePath: "attachments/\(attachmentID)/manifest.json",
            extractedTextRelativePath: "attachments/\(attachmentID)/derivatives/current/transcript.md",
            previewText: String(payload.transcriptMarkdown.prefix(2_000)),
            derivativeRefs: derivativeRefs,
            extractionReports: [
                AgentAttachmentExtractionReport(
                    attachmentID: attachmentID,
                    engine: .manual,
                    status: .extracted,
                    capabilitiesUsed: ["media-transcript", "local-provenance"],
                    derivativeRefs: derivativeRefs,
                    startedAt: now,
                    completedAt: now
                )
            ],
            createdAt: now,
            updatedAt: now,
            sourceDisplayPath: job.source.pageURLString
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: attachmentDirectory.appendingPathComponent("manifest.json"), options: [.atomic])
        try appendLedger(manifest, attachmentsDirectory: directories.attachments)
        return MediaTranscriptionAttachmentWriteResult(attachmentID: attachmentID, manifest: manifest, derivativeRefs: derivativeRefs)
    }

    private func writeDerivative(
        contents: String,
        filename: String,
        kind: AgentAttachmentDerivativeKind,
        attachmentID: String,
        currentDirectory: URL,
        runDirectory: URL,
        runID: String,
        now: Date,
        refs: inout [AgentAttachmentDerivativeRef]
    ) throws {
        let data = Data(contents.utf8)
        try data.write(to: currentDirectory.appendingPathComponent(filename), options: [.atomic])
        try data.write(to: runDirectory.appendingPathComponent(filename), options: [.atomic])
        let digest = sha256Hex(data)
        refs.append(AgentAttachmentDerivativeRef(kind: kind, relativePath: "attachments/\(attachmentID)/derivatives/current/\(filename)", byteCount: Int64(data.count), sha256: digest, createdAt: now))
        refs.append(AgentAttachmentDerivativeRef(kind: kind, relativePath: "attachments/\(attachmentID)/derivatives/runs/\(runID)/\(filename)", byteCount: Int64(data.count), sha256: digest, createdAt: now))
    }

    private func appendLedger(_ manifest: AgentAttachmentManifest, attachmentsDirectory: URL) throws {
        let lineEncoder = JSONEncoder()
        lineEncoder.dateEncodingStrategy = .iso8601
        let lineData = try lineEncoder.encode(manifest)
        let ledgerURL = attachmentsDirectory.appendingPathComponent("attachment-manifest.jsonl")
        if !FileManager.default.fileExists(atPath: ledgerURL.path) { FileManager.default.createFile(atPath: ledgerURL.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: ledgerURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: lineData)
        try handle.write(contentsOf: Data("\n".utf8))
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
