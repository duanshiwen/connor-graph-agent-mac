import Foundation
import CryptoKit
import UniformTypeIdentifiers
import ConnorGraphCore

/// 文件来源（业务数据层记录“这个文件是怎么进来的”）。
public enum FileArtifactSource: String, Codable, Sendable, Equatable {
    case session    // 用户在会话中交给康纳
    case imported   // 用户导入
    case generated  // 模型/工具生成
    case forwarded  // 转发/交接
    case other
}

/// 文件提取状态：能提取出文字就存派生文本用于搜索；读不了就只保留元数据。
public enum FileArtifactExtractionStatus: String, Codable, Sendable, Equatable {
    case textExtracted
    case partial
    case unreadable
}

/// 业务数据层的一条文件记录。文件字节独立于会话长期保留；fileID 由内容哈希派生，
/// 同内容复用，内容变化产生新 fileID（即新版本）。
public struct FileArtifactRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { fileID }
    public var fileID: String
    public var sha256: String
    public var originalName: String
    public var mimeType: String?
    public var byteCount: Int64
    public var source: FileArtifactSource
    public var extractionStatus: FileArtifactExtractionStatus
    public var summary: String?
    public var storedRelativePath: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastSeenAt: Date
    /// 附件类型（按文件名/扩展名分类，用于附件库筛选与展示）。
    public var kind: AgentAttachmentKind { FileArtifactStore.classifyKind(name: originalName) }

    public init(
        fileID: String,
        sha256: String,
        originalName: String,
        mimeType: String?,
        byteCount: Int64,
        source: FileArtifactSource,
        extractionStatus: FileArtifactExtractionStatus,
        summary: String?,
        storedRelativePath: String,
        createdAt: Date,
        updatedAt: Date,
        lastSeenAt: Date
    ) {
        self.fileID = fileID
        self.sha256 = sha256
        self.originalName = originalName
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.source = source
        self.extractionStatus = extractionStatus
        self.summary = summary
        self.storedRelativePath = storedRelativePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSeenAt = lastSeenAt
    }
}

public enum FileArtifactStoreError: Error, Equatable, CustomStringConvertible {
    case notRegularFile(String)
    case fileTooLarge(filename: String, maximumBytes: Int64)
    case storeQuotaExceeded(maximumBytes: Int64)
    case artifactNotFound(String)
    case invalidFileName(String)

    public var description: String {
        switch self {
        case .notRegularFile(let name): return "Not a regular file: \(name)"
        case .fileTooLarge(let filename, let maximumBytes): return "File \(filename) exceeds the \(maximumBytes) byte limit."
        case .storeQuotaExceeded(let maximumBytes): return "File store quota exceeded (maximum \(maximumBytes) bytes)."
        case .artifactNotFound(let id): return "No registered file with id \(id)."
        case .invalidFileName(let name): return "Invalid file name: \(name)"
        }
    }
}

/// 业务数据仓库：文件字节 + 元数据。不存进 Memory OS，也不喂给模型。
/// 同 sha256 复用同一 fileID；内容变化 -> 新 fileID（新版本）。
public struct FileArtifactStore: Sendable {
    public var paths: AppStoragePaths
    /// 单文件登记上限（默认 50MB）。
    public var maxRegistrationBytes: Int64
    /// 文件库总配额（默认 500MB）。
    public var maxTotalBytes: Int64

    public init(
        paths: AppStoragePaths,
        maxRegistrationBytes: Int64 = 50_000_000,
        maxTotalBytes: Int64 = 500_000_000
    ) {
        self.paths = paths
        self.maxRegistrationBytes = maxRegistrationBytes
        self.maxTotalBytes = maxTotalBytes
    }

    public static func fileID(forSHA256 sha256: String) -> String {
        "file:" + String(sha256.prefix(20))
    }

    /// 登记一个文件：复制字节、哈希、去重/版本、类型识别、尽力提取、写 manifest。
    public func register(
        from sourceURL: URL,
        filename: String? = nil,
        source: FileArtifactSource = .session,
        summary: String? = nil,
        now: Date = Date()
    ) throws -> FileArtifactRecord {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw FileArtifactStoreError.notRegularFile(sourceURL.lastPathComponent)
        }
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw FileArtifactStoreError.notRegularFile(sourceURL.lastPathComponent)
        }
        let byteCount = Int64(values.fileSize ?? 0)
        let displayName = (filename?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? sourceURL.lastPathComponent
        guard byteCount <= maxRegistrationBytes else {
            throw FileArtifactStoreError.fileTooLarge(filename: displayName, maximumBytes: maxRegistrationBytes)
        }
        let digest = try Self.sha256Hex(forItemAt: sourceURL)
        let fileID = Self.fileID(forSHA256: digest)
        let fileDirectory = paths.filesDirectory.appendingPathComponent(fileID, isDirectory: true)
        let manifestURL = fileDirectory.appendingPathComponent("manifest.json")

        if let existing = try? loadManifest(url: manifestURL) {
            // 同内容复用：刷新最近看到时间（严格递增，保证“最近附件”里被再次使用的文件排到最前）。
            let seenAt = max(now, existing.lastSeenAt.addingTimeInterval(0.001))
            let refreshed = FileArtifactRecord(
                fileID: existing.fileID,
                sha256: existing.sha256,
                originalName: existing.originalName,
                mimeType: existing.mimeType,
                byteCount: existing.byteCount,
                source: existing.source,
                extractionStatus: existing.extractionStatus,
                summary: existing.summary,
                storedRelativePath: existing.storedRelativePath,
                createdAt: existing.createdAt,
                updatedAt: existing.updatedAt,
                lastSeenAt: seenAt
            )
            try writeManifest(refreshed, to: manifestURL)
            return refreshed
        }

        let currentTotal = try totalBytes()
        guard currentTotal + byteCount <= maxTotalBytes else {
            throw FileArtifactStoreError.storeQuotaExceeded(maximumBytes: maxTotalBytes)
        }

        try fileManager.createDirectory(at: fileDirectory, withIntermediateDirectories: true)
        let sanitizedName = Self.sanitizedFilename(displayName)
        let originalDirectory = fileDirectory.appendingPathComponent("original", isDirectory: true)
        try fileManager.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
        let storedURL = originalDirectory.appendingPathComponent(sanitizedName)
        if fileManager.fileExists(atPath: storedURL.path) {
            try fileManager.removeItem(at: storedURL)
        }
        try fileManager.copyItem(at: sourceURL, to: storedURL)

        let mimeType = Self.mimeType(for: storedURL, fallbackName: displayName)
        let extraction = Self.attemptExtraction(fileURL: storedURL, filename: displayName)
        let storedRelativePath = "\(fileID)/original/\(sanitizedName)"
        let record = FileArtifactRecord(
            fileID: fileID,
            sha256: digest,
            originalName: displayName,
            mimeType: mimeType,
            byteCount: byteCount,
            source: source,
            extractionStatus: extraction.status,
            summary: summary ?? extraction.previewText,
            storedRelativePath: storedRelativePath,
            createdAt: now,
            updatedAt: now,
            lastSeenAt: now
        )
        try writeManifest(record, to: manifestURL)
        return record
    }

    /// 读取已登记文件的字节（供外发附件等运行时取用）。
    public func readBytes(fileID: String) throws -> Data {
        let record = try artifact(fileID: fileID)
        let url = paths.filesDirectory.appendingPathComponent(record.storedRelativePath)
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    public func artifact(fileID: String) throws -> FileArtifactRecord {
        let manifestURL = paths.filesDirectory.appendingPathComponent(fileID).appendingPathComponent("manifest.json")
        return try loadManifest(url: manifestURL)
    }

    /// 附件库分页结果。
    public struct FileArtifactPage: Sendable, Equatable {
        public var items: [FileArtifactRecord]
        public var total: Int
        public var page: Int
        public var pageSize: Int

        public init(items: [FileArtifactRecord], total: Int, page: Int, pageSize: Int) {
            self.items = items
            self.total = total
            self.page = page
            self.pageSize = pageSize
        }

        public var hasMore: Bool { page * pageSize + items.count < total }
    }

    /// 附件库分页查询：按「最近使用（lastSeenAt 降序）」排序，支持关键词 / 来源 / 类型筛选。
    /// - Parameters:
    ///   - page: 0 起始的页码。
    ///   - pageSize: 每页条数（默认 30，上限 200）。
    public func list(
        query: String? = nil,
        source: FileArtifactSource? = nil,
        kind: AgentAttachmentKind? = nil,
        page: Int = 0,
        pageSize: Int = 30
    ) -> FileArtifactPage {
        let needle = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let boundedPage = max(page, 0)
        let boundedPageSize = min(max(pageSize, 1), 200)
        let all = scanAll()
            .filter { record in
                if let source, record.source != source { return false }
                if let kind, record.kind != kind { return false }
                if !needle.isEmpty {
                    let haystack = [
                        record.originalName,
                        record.mimeType ?? "",
                        record.source.rawValue,
                        record.summary ?? ""
                    ].joined(separator: " ").lowercased()
                    guard haystack.contains(needle) else { return false }
                }
                return true
            }
            .sorted { $0.lastSeenAt > $1.lastSeenAt }
        let start = boundedPage * boundedPageSize
        guard start < all.count else {
            return FileArtifactPage(items: [], total: all.count, page: boundedPage, pageSize: boundedPageSize)
        }
        let items = Array(all[start..<min(start + boundedPageSize, all.count)])
        return FileArtifactPage(items: items, total: all.count, page: boundedPage, pageSize: boundedPageSize)
    }

    /// 兼容旧入口：按名称/类型/来源/摘要做不区分大小写的子串查找，最近使用优先，取前 [limit] 条。
    public func lookup(query: String?, limit: Int = 20) -> [FileArtifactRecord] {
        list(query: query, page: 0, pageSize: limit).items
    }

    /// 附件库全部记录（按最近使用降序）。
    public func recent(limit: Int = 50) -> [FileArtifactRecord] {
        list(page: 0, pageSize: limit).items
    }

    private func scanAll() -> [FileArtifactRecord] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: paths.filesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var records: [FileArtifactRecord] = []
        for entry in entries {
            guard let manifestURL = try? entry.appendingPathComponent("manifest.json") else { continue }
            guard let record = try? loadManifest(url: manifestURL) else { continue }
            records.append(record)
        }
        return records
    }

    /// 显式删除：字节与 manifest 一起移除（业务数据独立于会话，用户显式删除才删）。
    public func delete(fileID: String) throws {
        let fileManager = FileManager.default
        let url = paths.filesDirectory.appendingPathComponent(fileID, isDirectory: true)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    public func totalBytes() throws -> Int64 {
        lookup(query: nil, limit: Int.max).reduce(0) { $0 + $1.byteCount }
    }

    // MARK: - Internals

    private func loadManifest(url: URL) throws -> FileArtifactRecord {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileArtifactStoreError.artifactNotFound(url.deletingLastPathComponent().lastPathComponent)
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            // 兼容旧 manifest（秒级无小数）
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(raw)")
        }
        return try decoder.decode(FileArtifactRecord.self, from: data)
    }

    private func writeManifest(_ record: FileArtifactRecord, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: url, options: .atomic)
    }

    public static func sha256Hex(forItemAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func sanitizedFilename(_ name: String) -> String {
        let fallback = "file"
        var result = name.replacingOccurrences(of: "..", with: "_")
        let invalid = CharacterSet(charactersIn: "/\\:\0\n\r\t")
        result = result.components(separatedBy: invalid).joined(separator: "_")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? fallback : result
    }

    private static func mimeType(for url: URL, fallbackName: String) -> String? {
        let ext = url.pathExtension.isEmpty ? (fallbackName as NSString).pathExtension : url.pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return type.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }

    private static func attemptExtraction(fileURL: URL, filename: String) -> (status: FileArtifactExtractionStatus, previewText: String?) {
        let kind = attachmentKind(for: fileURL, filename: filename)
        guard let extraction = try? AttachmentTextExtraction.extract(fileURL: fileURL, kind: kind, maxBytes: 512_000) else {
            return (.unreadable, nil)
        }
        switch extraction.status {
        case .extracted:
            let preview = extraction.previewText?.nilIfBlank ?? extraction.markdown?.nilIfBlank
            return (.textExtracted, preview)
        case .failed:
            return (.partial, extraction.previewText)
        case .skippedOversize, .unsupported, .pending:
            return (.unreadable, nil)
        }
    }

    /// 按文件名/扩展名分类附件类型（附件库筛选与展示用）。
    public static func classifyKind(name: String) -> AgentAttachmentKind {
        attachmentKind(for: URL(fileURLWithPath: name), filename: name)
    }

    private static func attachmentKind(for url: URL, filename: String) -> AgentAttachmentKind {
        let ext = url.pathExtension.isEmpty ? (filename as NSString).pathExtension.lowercased() : url.pathExtension.lowercased()
        switch ext {
        case "txt", "text": return .text
        case "md", "markdown": return .markdown
        case "json": return .json
        case "csv": return .csv
        case "html", "htm": return .html
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp": return .image
        case "zip", "tar", "gz", "7z", "rar": return .archive
        case "mp3", "wav", "m4a", "aac", "flac": return .audio
        case "mp4", "mov", "mkv", "webm": return .video
        case "doc", "docx", "pages", "rtf", "odt": return .document
        case "xls", "xlsx", "numbers", "csv": return .spreadsheet
        case "ppt", "pptx", "key": return .presentation
        default: return .unknown
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
