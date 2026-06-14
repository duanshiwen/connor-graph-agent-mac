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
    case unsupportedImage
    case unsupportedPDF
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
        case .unsupportedImage: return "暂不支持图片文件"
        case .unsupportedPDF: return "暂不支持 PDF 文件"
        case .unsupportedAudio: return "暂不支持音频文件"
        case .unsupportedVideo: return "暂不支持视频文件"
        case .unsupportedOffice: return "暂不支持 Word / Excel / PowerPoint 文件"
        case .unsupportedIWork: return "暂不支持 Apple iWork 文件"
        case .unsupportedArchive: return "暂不支持压缩文件"
        case .unsupportedSVG: return "暂不支持 SVG 文件"
        case .unsupportedDatabase: return "暂不支持数据库文件"
        case .unsupportedExecutableOrBinary: return "暂不支持可执行、安装包或二进制文件"
        case .unsupportedUnknownExtension(let ext): return "暂不支持 .\(ext) 文件"
        case .fileTooLarge(let maxBytes): return "文件超过当前文本附件大小限制（\(ByteCountFormatter.string(fromByteCount: maxBytes, countStyle: .file))）"
        }
    }
}

public struct AttachmentImportPolicy: Sendable {
    public var maxAcceptedBytes: Int64

    public init(maxAcceptedBytes: Int64 = 512_000) {
        self.maxAcceptedBytes = maxAcceptedBytes
    }

    public func validate(url: URL, fileManager: FileManager = .default) -> AttachmentImportValidationResult {
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !ext.isEmpty else { return .rejected(.missingFileExtension) }

        if let byteCount = try? byteCount(url: url, fileManager: fileManager), byteCount > maxAcceptedBytes {
            return .rejected(.fileTooLarge(maxAcceptedBytes))
        }

        if let kind = Self.acceptedKind(forExtension: ext) {
            return .accepted(kind: kind)
        }
        return .rejected(Self.rejectionReason(forExtension: ext))
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
        default:
            return nil
        }
    }

    public static func rejectionReason(forExtension ext: String) -> AttachmentImportRejectionReason {
        switch ext.lowercased() {
        case "html", "htm": return .unsupportedHTML
        case "svg": return .unsupportedSVG
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "avif", "bmp", "ico": return .unsupportedImage
        case "pdf": return .unsupportedPDF
        case "mp3", "wav", "m4a", "aac", "flac", "ogg": return .unsupportedAudio
        case "mp4", "mov", "mkv", "avi", "webm": return .unsupportedVideo
        case "doc", "docx", "xls", "xlsx", "ppt", "pptx", "rtf": return .unsupportedOffice
        case "pages", "numbers", "keynote": return .unsupportedIWork
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz": return .unsupportedArchive
        case "sqlite", "db": return .unsupportedDatabase
        case "dmg", "pkg", "exe", "app", "bin": return .unsupportedExecutableOrBinary
        default: return .unsupportedUnknownExtension(ext.lowercased())
        }
    }

    private func byteCount(url: URL, fileManager: FileManager) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize { return Int64(fileSize) }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
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
