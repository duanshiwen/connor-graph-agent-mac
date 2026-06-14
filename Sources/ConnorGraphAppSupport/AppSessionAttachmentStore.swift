import CryptoKit
import Foundation
import ConnorGraphCore

public struct AppSessionAttachmentStore: Sendable {
    public var paths: AppStoragePaths
    public var maxTextExtractionBytes: Int64

    public init(
        paths: AppStoragePaths,
        maxTextExtractionBytes: Int64 = 512_000
    ) {
        self.paths = paths
        self.maxTextExtractionBytes = maxTextExtractionBytes
    }

    public func importFile(
        at sourceURL: URL,
        sessionID: String,
        now: Date = Date()
    ) throws -> AgentAttachmentManifest {
        let fileManager = FileManager.default
        let attachmentID = UUID().uuidString
        let originalFilename = sourceURL.lastPathComponent
        let normalizedFilename = Self.sanitizedFilename(originalFilename)
        let directories = try paths.ensureSessionArtifactDirectories(sessionID: sessionID, fileManager: fileManager)
        try fileManager.createDirectory(at: directories.attachments, withIntermediateDirectories: true)

        let attachmentDirectory = directories.attachments.appendingPathComponent(attachmentID, isDirectory: true)
        let originalDirectory = attachmentDirectory.appendingPathComponent("original", isDirectory: true)
        let derivativesDirectory = attachmentDirectory.appendingPathComponent("derivatives", isDirectory: true)
        try fileManager.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: derivativesDirectory, withIntermediateDirectories: true)

        let originalURL = originalDirectory.appendingPathComponent(normalizedFilename)
        if fileManager.fileExists(atPath: originalURL.path) {
            try fileManager.removeItem(at: originalURL)
        }
        try fileManager.copyItem(at: sourceURL, to: originalURL)

        let data = try Data(contentsOf: originalURL)
        let digest = Self.sha256Hex(data)
        let kind = Self.kind(for: sourceURL)
        let fileExtension = sourceURL.pathExtension.isEmpty ? nil : sourceURL.pathExtension.lowercased()
        var extractedPath: String?
        var previewText: String?
        var extractionStatus: AgentAttachmentExtractionStatus = .pending

        let extraction = try AttachmentTextExtraction.extract(fileURL: originalURL, kind: kind, maxBytes: maxTextExtractionBytes)
        extractionStatus = extraction.status
        previewText = extraction.previewText
        var derivativeRefs: [AgentAttachmentDerivativeRef] = []
        if let markdown = extraction.markdown {
            let extractedURL = derivativesDirectory.appendingPathComponent("extracted.md")
            try markdown.write(to: extractedURL, atomically: true, encoding: .utf8)
            extractedPath = "attachments/\(attachmentID)/derivatives/extracted.md"
            let extractedData = Data(markdown.utf8)
            derivativeRefs.append(AgentAttachmentDerivativeRef(
                kind: .extractedMarkdown,
                relativePath: extractedPath!,
                byteCount: Int64(extractedData.count),
                sha256: Self.sha256Hex(extractedData),
                createdAt: now
            ))
        }
        let extractionReport = AgentAttachmentExtractionReport(
            attachmentID: attachmentID,
            engine: .builtinText,
            status: extractionStatus,
            capabilitiesUsed: AttachmentTextExtraction.supports(kind: kind) ? ["text"] : [],
            derivativeRefs: derivativeRefs,
            startedAt: now,
            completedAt: now
        )

        let manifest = AgentAttachmentManifest(
            id: attachmentID,
            displayName: originalFilename,
            originalFilename: originalFilename,
            normalizedFilename: normalizedFilename,
            kind: kind,
            mimeType: Self.mimeType(for: kind, fileExtension: fileExtension),
            fileExtension: fileExtension,
            byteCount: Int64(data.count),
            sha256: digest,
            lifecycleStatus: .ready,
            extractionStatus: extractionStatus,
            storedRelativePath: "attachments/\(attachmentID)/original/\(normalizedFilename)",
            manifestRelativePath: "attachments/\(attachmentID)/manifest.json",
            extractedTextRelativePath: extractedPath,
            previewText: previewText,
            derivativeRefs: derivativeRefs,
            extractionReports: [extractionReport],
            createdAt: now,
            updatedAt: now,
            sourceDisplayPath: sourceURL.path
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: attachmentDirectory.appendingPathComponent("manifest.json"), options: [.atomic])

        let lineEncoder = JSONEncoder()
        lineEncoder.dateEncodingStrategy = .iso8601
        let lineData = try lineEncoder.encode(manifest)
        let ledgerURL = directories.attachments.appendingPathComponent("attachment-manifest.jsonl")
        if !fileManager.fileExists(atPath: ledgerURL.path) {
            fileManager.createFile(atPath: ledgerURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: ledgerURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: lineData)
        try handle.write(contentsOf: Data("\n".utf8))

        return manifest
    }

    public func loadManifest(sessionID: String, attachmentID: String) throws -> AgentAttachmentManifest {
        let url = paths.sessionArtifactDirectories(sessionID: sessionID)
            .attachments
            .appendingPathComponent(attachmentID, isDirectory: true)
            .appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgentAttachmentManifest.self, from: data)
    }

    public static func sanitizedFilename(_ filename: String) -> String {
        let fallback = "attachment"
        var result = filename.replacingOccurrences(of: "..", with: "_")
        let invalid = CharacterSet(charactersIn: "/\\:\0\n\r\t")
        result = result.components(separatedBy: invalid).joined(separator: "_")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? fallback : result
    }

    public static func kind(for url: URL) -> AgentAttachmentKind {
        switch url.pathExtension.lowercased() {
        case "txt", "log": return .text
        case "md", "markdown": return .markdown
        case "json", "jsonl": return .json
        case "csv", "tsv": return .csv
        case "html", "htm": return .html
        case "swift", "rs", "py", "js", "ts", "tsx", "jsx", "java", "kt", "go", "rb", "sh", "sql", "xml", "yaml", "yml": return .code
        case "png", "jpg", "jpeg", "webp", "gif", "heic": return .image
        case "pdf": return .pdf
        case "doc", "docx", "rtf", "pages", "epub": return .document
        case "xls", "xlsx", "numbers": return .spreadsheet
        case "zip", "tar", "gz", "7z": return .archive
        case "mp3", "wav", "m4a", "aac": return .audio
        case "mp4", "mov", "avi", "mkv": return .video
        default: return .unknown
        }
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func mimeType(for kind: AgentAttachmentKind, fileExtension: String?) -> String? {
        switch kind {
        case .text: return "text/plain"
        case .markdown: return "text/markdown"
        case .json: return "application/json"
        case .csv: return "text/csv"
        case .html: return "text/html"
        case .pdf: return "application/pdf"
        case .image:
            if let fileExtension { return "image/\(fileExtension == "jpg" ? "jpeg" : fileExtension)" }
            return "image/*"
        default: return nil
        }
    }
}
