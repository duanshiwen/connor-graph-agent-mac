import Foundation
import ConnorGraphCore

public struct AttachmentRejectedFile: Sendable, Equatable, Identifiable {
    public var id: String
    public var filename: String
    public var reason: AttachmentImportRejectionReason

    public init(id: String = UUID().uuidString, filename: String, reason: AttachmentImportRejectionReason) {
        self.id = id
        self.filename = filename
        self.reason = reason
    }
}

public struct AttachmentImportBatchResult: Sendable, Equatable {
    public var accepted: [AgentMessageAttachmentRef]
    public var rejected: [AttachmentRejectedFile]

    public init(accepted: [AgentMessageAttachmentRef] = [], rejected: [AttachmentRejectedFile] = []) {
        self.accepted = accepted
        self.rejected = rejected
    }
}

public enum AttachmentImportValidationResult: Sendable, Equatable {
    case accepted(kind: AgentAttachmentKind)
    case rejected(AttachmentImportRejectionReason)
}

public enum AttachmentImportRejectionReason: Sendable, Equatable, CustomStringConvertible {
    case missingFileExtension
    case unsupportedHTML
    case unsupportedPDF
    case unsupportedPresentation
    case unsupportedAudio
    case unsupportedVideo
    case unsupportedOffice
    case unsupportedIWork
    case unsupportedArchive
    case unsupportedSVG
    case unsupportedDatabase
    case unsupportedExecutableOrBinary
    case unsupportedUnknownExtension(String)
    case fileTooLarge(Int64)

    public var description: String { userMessage }

    public var userMessage: String {
        switch self {
        case .missingFileExtension: return "缺少文件扩展名"
        case .unsupportedHTML: return "暂不支持 HTML 文件"
        case .unsupportedPDF: return "暂不支持 PDF 文件"
        case .unsupportedPresentation: return "暂不支持 PowerPoint 演示文稿"
        case .unsupportedAudio: return "暂不支持音频文件"
        case .unsupportedVideo: return "暂不支持视频文件"
        case .unsupportedOffice: return "暂不支持 Word / Excel / PowerPoint 文件"
        case .unsupportedIWork: return "暂不支持 Apple iWork 文件"
        case .unsupportedArchive: return "暂不支持压缩文件"
        case .unsupportedSVG: return "暂不支持 SVG 文件"
        case .unsupportedDatabase: return "暂不支持数据库文件"
        case .unsupportedExecutableOrBinary: return "暂不支持可执行、安装包或二进制文件"
        case .unsupportedUnknownExtension(let ext): return "暂不支持 .\(ext) 文件"
        case .fileTooLarge(let maxBytes): return "文件超过当前附件大小限制（\(ByteCountFormatter.string(fromByteCount: maxBytes, countStyle: .file))）"
        }
    }
}

public struct AttachmentImportPolicy: Sendable {
    public var maxAcceptedBytes: Int64
    public var maxImageBytes: Int64
    public var maxDocumentBytes: Int64

    public init(maxAcceptedBytes: Int64 = 512_000, maxImageBytes: Int64 = 10_000_000, maxDocumentBytes: Int64 = 25_000_000) {
        self.maxAcceptedBytes = maxAcceptedBytes
        self.maxImageBytes = maxImageBytes
        self.maxDocumentBytes = maxDocumentBytes
    }

    public func validate(url: URL, fileManager: FileManager = .default) -> AttachmentImportValidationResult {
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !ext.isEmpty else { return .rejected(.missingFileExtension) }

        guard let kind = Self.acceptedKind(forExtension: ext) else {
            return .rejected(Self.rejectionReason(forExtension: ext))
        }

        let byteLimit = byteLimit(for: kind)
        if let byteCount = try? byteCount(url: url, fileManager: fileManager), byteCount > byteLimit {
            return .rejected(.fileTooLarge(byteLimit))
        }

        return .accepted(kind: kind)
    }

    public static func acceptedKind(forExtension ext: String) -> AgentAttachmentKind? {
        switch ext.lowercased() {
        case "txt", "log": return .text
        case "md", "markdown": return .markdown
        case "json", "jsonl": return .json
        case "csv", "tsv": return .csv
        case "xml", "yaml", "yml": return .code
        case "swift", "py", "js", "ts", "tsx", "jsx", "rs", "go", "java", "kt", "c", "cpp", "h", "hpp", "cs", "rb", "php", "sh", "zsh", "bash", "sql", "css", "scss":
            return .code
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "ico", "tif", "tiff":
            return .image
        case "pdf": return .pdf
        case "doc", "docx", "rtf", "pages": return .document
        case "xls", "xlsx", "numbers": return .spreadsheet
        case "ppt", "pptx", "keynote": return .presentation
        default:
            return nil
        }
    }

    public static func rejectionReason(forExtension ext: String) -> AttachmentImportRejectionReason {
        switch ext.lowercased() {
        case "html", "htm": return .unsupportedHTML
        case "svg", "avif": return .unsupportedSVG
        case "mp3", "wav", "m4a", "aac", "flac", "ogg": return .unsupportedAudio
        case "mp4", "mov", "mkv", "avi", "webm": return .unsupportedVideo
        case "pages", "numbers", "keynote": return .unsupportedIWork
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz": return .unsupportedArchive
        case "sqlite", "db": return .unsupportedDatabase
        case "dmg", "pkg", "exe", "app", "bin": return .unsupportedExecutableOrBinary
        default: return .unsupportedUnknownExtension(ext.lowercased())
        }
    }

    private func byteLimit(for kind: AgentAttachmentKind) -> Int64 {
        switch kind {
        case .image:
            return maxImageBytes
        case .pdf, .document, .spreadsheet, .presentation:
            return maxDocumentBytes
        default:
            return maxAcceptedBytes
        }
    }

    private func byteCount(url: URL, fileManager: FileManager) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        if values.isSymbolicLink == true { return 0 }
        if values.isRegularFile == true {
            if let fileSize = values.fileSize { return Int64(fileSize) }
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        }
        if values.isDirectory == true {
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return 0 }
            var total: Int64 = 0
            for case let childURL as URL in enumerator {
                let childValues = try childURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard childValues.isSymbolicLink != true, childValues.isRegularFile == true else { continue }
                if let fileSize = childValues.fileSize {
                    total += Int64(fileSize)
                }
            }
            return total
        }
        return 0
    }
}

public enum AppSessionAttachmentImportError: Error, Equatable, CustomStringConvertible {
    case rejected(filename: String, reason: AttachmentImportRejectionReason)

    public var description: String {
        switch self {
        case .rejected(let filename, let reason): return "\(filename)：\(reason.userMessage)"
        }
    }
}
