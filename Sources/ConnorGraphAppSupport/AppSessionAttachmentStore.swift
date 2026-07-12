import AVFoundation
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
        now: Date = Date(),
        origin: AgentAttachmentOrigin = .userImported,
        generationMetadata: AgentAttachmentGenerationMetadata? = nil
    ) throws -> AgentAttachmentManifest {
        let fileManager = FileManager.default
        let importPolicy = AttachmentImportPolicy(maxAcceptedBytes: maxTextExtractionBytes)
        let originalFilename = sourceURL.lastPathComponent
        let validation = importPolicy.validate(url: sourceURL, fileManager: fileManager)
        let kind: AgentAttachmentKind
        switch validation {
        case .accepted(let acceptedKind):
            kind = acceptedKind
        case .rejected(let reason):
            throw AppSessionAttachmentImportError.rejected(filename: originalFilename, reason: reason)
        }
        let attachmentID = UUID().uuidString
        let runID = Self.derivativeRunID(now: now, engine: .builtinText)
        let normalizedFilename = Self.sanitizedFilename(originalFilename)
        let directories = try paths.ensureSessionArtifactDirectories(sessionID: sessionID, fileManager: fileManager)
        try fileManager.createDirectory(at: directories.attachments, withIntermediateDirectories: true)

        let attachmentDirectory = directories.attachments.appendingPathComponent(attachmentID, isDirectory: true)
        let originalDirectory = attachmentDirectory.appendingPathComponent("original", isDirectory: true)
        let derivativesDirectory = attachmentDirectory.appendingPathComponent("derivatives", isDirectory: true)
        let currentDerivativesDirectory = derivativesDirectory.appendingPathComponent("current", isDirectory: true)
        let runDerivativesDirectory = derivativesDirectory
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
        try fileManager.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: currentDerivativesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runDerivativesDirectory, withIntermediateDirectories: true)

        let originalURL = originalDirectory.appendingPathComponent(normalizedFilename)
        if fileManager.fileExists(atPath: originalURL.path) {
            try fileManager.removeItem(at: originalURL)
        }
        try fileManager.copyItem(at: sourceURL, to: originalURL)

        let byteCount = try Self.byteCount(forItemAt: originalURL)
        let digest = try Self.sha256Hex(forItemAt: originalURL)
        let fileExtension = sourceURL.pathExtension.isEmpty ? nil : sourceURL.pathExtension.lowercased()
        var extractedPath: String?
        var previewText: String?
        var extractionStatus: AgentAttachmentExtractionStatus = Self.shouldEnqueueExtraction(kind: kind) ? .pending : .pending
        var derivativeRefs: [AgentAttachmentDerivativeRef] = []
        var extractionReports: [AgentAttachmentExtractionReport] = []
        let mediaMetadata = Self.mediaMetadata(for: originalURL, kind: kind)

        if !Self.shouldEnqueueExtraction(kind: kind) {
            let extraction = try AttachmentTextExtraction.extract(fileURL: originalURL, kind: kind, maxBytes: maxTextExtractionBytes)
            extractionStatus = extraction.status
            previewText = extraction.previewText
            if let markdown = extraction.markdown {
            let currentExtractedURL = currentDerivativesDirectory.appendingPathComponent("extracted.md")
            let runExtractedURL = runDerivativesDirectory.appendingPathComponent("extracted.md")
            try markdown.write(to: currentExtractedURL, atomically: true, encoding: .utf8)
            try markdown.write(to: runExtractedURL, atomically: true, encoding: .utf8)
            extractedPath = "attachments/\(attachmentID)/derivatives/current/extracted.md"
            let runExtractedPath = "attachments/\(attachmentID)/derivatives/runs/\(runID)/extracted.md"
            let extractedData = Data(markdown.utf8)
            let extractedDigest = Self.sha256Hex(extractedData)
            derivativeRefs.append(AgentAttachmentDerivativeRef(
                kind: .extractedMarkdown,
                relativePath: extractedPath!,
                byteCount: Int64(extractedData.count),
                sha256: extractedDigest,
                createdAt: now
            ))
            derivativeRefs.append(AgentAttachmentDerivativeRef(
                kind: .extractedMarkdown,
                relativePath: runExtractedPath,
                byteCount: Int64(extractedData.count),
                sha256: extractedDigest,
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
            extractionReports.append(extractionReport)
        }

        let manifest = AgentAttachmentManifest(
            id: attachmentID,
            displayName: originalFilename,
            originalFilename: originalFilename,
            normalizedFilename: normalizedFilename,
            kind: kind,
            mimeType: Self.mimeType(for: kind, fileExtension: fileExtension),
            fileExtension: fileExtension,
            byteCount: byteCount,
            sha256: digest,
            lifecycleStatus: .ready,
            extractionStatus: extractionStatus,
            storedRelativePath: "attachments/\(attachmentID)/original/\(normalizedFilename)",
            manifestRelativePath: "attachments/\(attachmentID)/manifest.json",
            extractedTextRelativePath: extractedPath,
            previewText: previewText,
            derivativeRefs: derivativeRefs,
            extractionReports: extractionReports,
            createdAt: now,
            updatedAt: now,
            sourceDisplayPath: origin == .userImported ? sourceURL.path : nil,
            origin: origin,
            generationMetadata: generationMetadata,
            mediaMetadata: mediaMetadata
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: attachmentDirectory.appendingPathComponent("manifest.json"), options: [.atomic])

        if Self.shouldEnqueueExtraction(kind: kind) {
            let job = AgentAttachmentExtractionJob(
                sessionID: sessionID,
                attachmentID: attachmentID,
                requestedCapabilities: Self.requestedCapabilities(for: kind),
                createdAt: now
            )
            try AttachmentExtractionJobStore(paths: paths).append(job)
        }

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
        case "swift", "rs", "py", "js", "ts", "tsx", "jsx", "java", "kt", "go", "rb", "sh", "sql", "xml", "yaml", "yml", "c", "cpp", "h", "hpp", "cs", "php", "zsh", "bash", "css", "scss": return .code
        case "png", "jpg", "jpeg", "webp", "gif", "heic", "bmp", "ico", "tif", "tiff": return .image
        case "pdf": return .pdf
        case "doc", "docx", "rtf", "pages", "epub": return .document
        case "xls", "xlsx", "numbers": return .spreadsheet
        case "ppt", "pptx", "keynote": return .presentation
        case "zip", "tar", "gz", "7z": return .archive
        case "mp3", "wav", "m4a", "aac": return .audio
        case "mp4", "mov", "avi", "mkv": return .video
        default: return .unknown
        }
    }

    public static func shouldEnqueueExtraction(kind: AgentAttachmentKind) -> Bool {
        switch kind {
        case .pdf, .document, .spreadsheet, .presentation:
            return true
        default:
            return false
        }
    }

    public static func requestedCapabilities(for kind: AgentAttachmentKind) -> [String] {
        switch kind {
        case .pdf:
            return ["pdf-selectable-text", "document-to-markdown"]
        case .document, .spreadsheet, .presentation:
            return ["document-to-markdown"]
        default:
            return []
        }
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(forItemAt url: URL, fileManager: FileManager = .default) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true { return sha256Hex(Data()) }
        if values.isRegularFile == true {
            return sha256Hex(try Data(contentsOf: url))
        }
        if values.isDirectory == true {
            var hasher = SHA256()
            for childURL in try regularFileChildren(of: url, fileManager: fileManager) {
                let relativePath = childURL.path.replacingOccurrences(of: url.path + "/", with: "")
                hasher.update(data: Data(relativePath.utf8))
                hasher.update(data: Data([0]))
                hasher.update(data: try Data(contentsOf: childURL))
                hasher.update(data: Data([0]))
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        return sha256Hex(Data())
    }

    public static func byteCount(forItemAt url: URL, fileManager: FileManager = .default) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        if values.isSymbolicLink == true { return 0 }
        if values.isRegularFile == true {
            if let fileSize = values.fileSize { return Int64(fileSize) }
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        }
        if values.isDirectory == true {
            var total: Int64 = 0
            for childURL in try regularFileChildren(of: url, fileManager: fileManager) {
                let childValues = try childURL.resourceValues(forKeys: [.fileSizeKey])
                total += Int64(childValues.fileSize ?? 0)
            }
            return total
        }
        return 0
    }

    private static func regularFileChildren(of root: URL, fileManager: FileManager) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [URL] = []
        for case let childURL as URL in enumerator {
            let values = try childURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            files.append(childURL)
        }
        return files.sorted { $0.path < $1.path }
    }

    public static func derivativeRunID(now: Date, engine: AgentAttachmentExtractionEngine) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: now)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
        return "\(timestamp)-\(engine.rawValue)-\(UUID().uuidString.prefix(8))"
    }

    private static func mediaMetadata(for url: URL, kind: AgentAttachmentKind) -> AgentAttachmentMediaMetadata? {
        guard kind == .audio else { return nil }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let duration = format.sampleRate > 0 ? Double(file.length) / format.sampleRate : nil
        return AgentAttachmentMediaMetadata(
            durationSeconds: duration,
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount)
        )
    }

    private static func mimeType(for kind: AgentAttachmentKind, fileExtension: String?) -> String? {
        switch kind {
        case .text: return "text/plain"
        case .markdown: return "text/markdown"
        case .json: return "application/json"
        case .csv: return "text/csv"
        case .image:
            switch fileExtension?.lowercased() {
            case "png": return "image/png"
            case "jpg", "jpeg": return "image/jpeg"
            case "gif": return "image/gif"
            case "webp": return "image/webp"
            case "heic": return "image/heic"
            case "bmp": return "image/bmp"
            case "ico": return "image/x-icon"
            case "tif", "tiff": return "image/tiff"
            default: return "image/*"
            }
        case .pdf:
            return "application/pdf"
        case .document:
            switch fileExtension?.lowercased() {
            case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            case "doc": return "application/msword"
            case "rtf": return "application/rtf"
            default: return "application/document"
            }
        case .spreadsheet:
            switch fileExtension?.lowercased() {
            case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            case "xls": return "application/vnd.ms-excel"
            default: return "application/spreadsheet"
            }
        case .presentation:
            switch fileExtension?.lowercased() {
            case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
            case "ppt": return "application/vnd.ms-powerpoint"
            default: return "application/presentation"
            }
        case .audio:
            switch fileExtension?.lowercased() {
            case "mp3": return "audio/mpeg"
            case "wav": return "audio/wav"
            case "m4a": return "audio/mp4"
            case "aac": return "audio/aac"
            default: return "audio/*"
            }
        default: return nil
        }
    }
}
