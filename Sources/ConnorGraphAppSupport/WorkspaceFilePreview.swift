import Foundation
import UniformTypeIdentifiers

public enum WorkspaceFilePreviewRenderer: String, Sendable, Equatable {
    case markdown
    case monospacedText
    case plainText
    case pdf
    case quickLook
    case html
    case unsupported
}

public enum WorkspaceCodeHighlightKind: String, Sendable, Equatable {
    case comment
    case string
    case keyword
    case number
}

public struct WorkspaceCodeHighlightSpan: Sendable, Equatable {
    public var location: Int
    public var length: Int
    public var kind: WorkspaceCodeHighlightKind

    public init(location: Int, length: Int, kind: WorkspaceCodeHighlightKind) {
        self.location = location
        self.length = length
        self.kind = kind
    }
}

public struct WorkspaceFilePreviewModel: Identifiable, Sendable, Equatable {
    public var id: String { node.id }
    public var node: WorkspaceFileNode
    public var renderer: WorkspaceFilePreviewRenderer
    public var body: String
    public var subtitle: String
    public var encodingName: String?
    public var message: String?
    public var loadedByteCount: Int
    public var isTruncated: Bool
    public var codeHighlightSpans: [WorkspaceCodeHighlightSpan]

    public init(
        node: WorkspaceFileNode,
        renderer: WorkspaceFilePreviewRenderer,
        body: String = "",
        subtitle: String,
        encodingName: String? = nil,
        message: String? = nil,
        loadedByteCount: Int = 0,
        isTruncated: Bool = false,
        codeHighlightSpans: [WorkspaceCodeHighlightSpan] = []
    ) {
        self.node = node
        self.renderer = renderer
        self.body = body
        self.subtitle = subtitle
        self.encodingName = encodingName
        self.message = message
        self.loadedByteCount = loadedByteCount
        self.isTruncated = isTruncated
        self.codeHighlightSpans = codeHighlightSpans
    }
}

public actor WorkspaceFilePreviewLoader {
    public static let defaultMaximumTextByteCount = 2 * 1_024 * 1_024

    private let maximumTextByteCount: Int
    private let decoder: TextDecodingService

    public init(
        maximumTextByteCount: Int = WorkspaceFilePreviewLoader.defaultMaximumTextByteCount,
        decoder: TextDecodingService = TextDecodingService()
    ) {
        self.maximumTextByteCount = maximumTextByteCount
        self.decoder = decoder
    }

    public func load(_ node: WorkspaceFileNode, textByteLimit: Int? = nil) -> WorkspaceFilePreviewModel {
        var renderer = Self.renderer(for: node.url)
        let byteCount = node.byteCount ?? Self.fileSize(at: node.url)
        let subtitle = Self.subtitle(for: node, byteCount: byteCount)

        if renderer == .quickLook, Self.shouldDetectTextContent(at: node.url),
           let detected = Self.detectedTextRenderer(at: node.url) {
            renderer = detected
        }

        guard [.markdown, .monospacedText, .plainText].contains(renderer) else {
            let message = renderer == .unsupported ? "当前文件类型暂不支持应用内预览。" : nil
            return WorkspaceFilePreviewModel(node: node, renderer: renderer, subtitle: subtitle, message: message)
        }

        do {
            let limit = max(1, textByteLimit ?? maximumTextByteCount)
            let handle = try FileHandle(forReadingFrom: node.url)
            defer { try? handle.close() }
            let candidate = try handle.read(upToCount: limit + 1) ?? Data()
            let isTruncated = candidate.count > limit || byteCount.map { $0 > Int64(limit) } == true
            let data = Data(candidate.prefix(limit))
            let decoded = try decoder.decode(TextDecodingRequest(data: data, allowLossy: isTruncated))
            let highlights = renderer == .monospacedText
                ? WorkspaceCodeSyntaxHighlighter.spans(in: decoded.text)
                : []
            return WorkspaceFilePreviewModel(
                node: node,
                renderer: renderer,
                body: decoded.text,
                subtitle: subtitle,
                encodingName: decoded.encodingName,
                message: isTruncated
                    ? "当前显示前 \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))，可按需继续加载。"
                    : nil,
                loadedByteCount: data.count,
                isTruncated: isTruncated,
                codeHighlightSpans: highlights
            )
        } catch {
            return WorkspaceFilePreviewModel(
                node: node,
                renderer: .unsupported,
                subtitle: subtitle,
                message: "无法读取文件预览：\(error.localizedDescription)"
            )
        }
    }

    public nonisolated static func renderer(for url: URL) -> WorkspaceFilePreviewRenderer {
        let extensionName = url.pathExtension.lowercased()
        if ["html", "htm"].contains(extensionName) { return .html }
        if ["md", "markdown"].contains(extensionName) { return .markdown }
        if extensionName == "pdf" { return .pdf }
        if monospacedTextExtensions.contains(extensionName) { return .monospacedText }
        if plainTextExtensions.contains(extensionName) { return .plainText }
        if archiveExtensions.contains(extensionName) { return .unsupported }

        guard let type = UTType(filenameExtension: extensionName) else { return .quickLook }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .sourceCode) || type.conforms(to: .json) || type.conforms(to: .xml) { return .monospacedText }
        if type.conforms(to: .text) { return .plainText }
        return .quickLook
    }

    private nonisolated static let monospacedTextExtensions: Set<String> = [
        "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cs", "java", "kt", "kts",
        "js", "jsx", "ts", "tsx", "py", "rb", "php", "rs", "go", "sh", "bash", "zsh",
        "fish", "sql", "css", "scss", "sass", "less", "json", "jsonl", "yaml", "yml", "toml",
        "plist", "xml", "csv", "tsv", "ini", "conf", "env", "gitignore"
    ]
    private nonisolated static let plainTextExtensions: Set<String> = ["txt", "log", "rtf"]
    private nonisolated static let archiveExtensions: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "xz", "rar", "7z"]
    private nonisolated static let knownQuickLookExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "webp", "tif", "tiff", "bmp", "svg",
        "doc", "docx", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "key",
        "mp3", "m4a", "wav", "aac", "flac", "mp4", "mov", "m4v", "avi"
    ]
    private nonisolated static let codeFilenames: Set<String> = [
        "makefile", "dockerfile", "gemfile", "rakefile", "podfile", "brewfile", "justfile",
        "package.resolved", ".gitignore", ".gitattributes", ".editorconfig"
    ]

    private nonisolated static func shouldDetectTextContent(at url: URL) -> Bool {
        let extensionName = url.pathExtension.lowercased()
        return !knownQuickLookExtensions.contains(extensionName) && !archiveExtensions.contains(extensionName)
    }

    private nonisolated static func detectedTextRenderer(at url: URL) -> WorkspaceFilePreviewRenderer? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16 * 1_024), !data.isEmpty else {
            return .plainText
        }
        if data.contains(0) { return nil }
        guard let decoded = try? TextDecodingService().decode(TextDecodingRequest(data: data, allowLossy: false)) else { return nil }
        let scalarCount = max(1, decoded.text.unicodeScalars.count)
        guard Double(decoded.controlCharacterCount) / Double(scalarCount) < 0.01 else { return nil }

        let filename = url.lastPathComponent.lowercased()
        if codeFilenames.contains(filename) || decoded.text.hasPrefix("#!") || looksLikeCode(decoded.text) {
            return .monospacedText
        }
        return .plainText
    }

    private nonisolated static func looksLikeCode(_ text: String) -> Bool {
        let sample = String(text.prefix(2_000))
        let signals = ["import ", "func ", "class ", "struct ", "const ", "let ", "var ", "def ", "fn ", "=>", "</"]
        return signals.contains { sample.contains($0) }
    }

    private nonisolated static func fileSize(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    private nonisolated static func subtitle(for node: WorkspaceFileNode, byteCount: Int64?) -> String {
        let size = byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "大小未知"
        return "\(node.relativePath) · \(size)"
    }
}

private enum WorkspaceCodeSyntaxHighlighter {
    private static let maximumUTF16Length = 256 * 1_024
    private static let maximumSpanCount = 5_000

    static func spans(in text: String) -> [WorkspaceCodeHighlightSpan] {
        let source = text as NSString
        let scanLength = min(source.length, maximumUTF16Length)
        guard scanLength > 0 else { return [] }
        let range = NSRange(location: 0, length: scanLength)
        var spans: [WorkspaceCodeHighlightSpan] = []

        append(pattern: #"\b(?:class|struct|enum|protocol|extension|func|let|var|import|return|if|else|for|while|switch|case|break|continue|guard|throw|throws|try|catch|async|await|actor|public|private|internal|static|final|const|function|def|fn|use|package|interface|new|true|false|null|nil|self|Self)\b"#, kind: .keyword, source: source, range: range, to: &spans)
        append(pattern: #"\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?)\b"#, kind: .number, source: source, range: range, to: &spans)
        append(pattern: #"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#, kind: .string, source: source, range: range, to: &spans)
        append(pattern: #"(?m)//.*$|#.*$|/\*[\s\S]*?\*/"#, kind: .comment, source: source, range: range, to: &spans)
        return Array(spans.prefix(maximumSpanCount))
    }

    private static func append(
        pattern: String,
        kind: WorkspaceCodeHighlightKind,
        source: NSString,
        range: NSRange,
        to spans: inout [WorkspaceCodeHighlightSpan]
    ) {
        guard spans.count < maximumSpanCount, let regex = try? NSRegularExpression(pattern: pattern) else { return }
        regex.enumerateMatches(in: source as String, range: range) { match, _, stop in
            guard let match else { return }
            spans.append(.init(location: match.range.location, length: match.range.length, kind: kind))
            if spans.count >= maximumSpanCount { stop.pointee = true }
        }
    }
}
