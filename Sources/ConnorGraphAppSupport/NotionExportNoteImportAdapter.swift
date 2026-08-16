import Foundation
import CryptoKit
import ConnorGraphCore

public enum NotionDatabaseImportStrategy: String, Sendable, Codable {
    case childPagesOnly = "child_pages_only"
    case databaseSummary = "database_summary"
    case rowAsNote = "row_as_note"
}

/// 将 Notion 的 Markdown & CSV 导出（文件夹，或经 `NotionExportSourceResolver` 解压后的文件夹）导入为笔记。
///
/// Notion 导出结构（已核对官方导出行为）：
/// - 每个页面是一个独立文件 `页面标题 <32位hex>.md`（或 .html），子页面在文件夹树中；
/// - 页面之间的"页面链接块 / link-to-page"在导出的 Markdown 中形如
///   `[标题](相对路径.md)`（目标页被一起导出）或 `https://www.notion.so/...`（目标页未导出）；
/// - 数据库导出为 CSV + 每行一个 .md；
/// - 图片等资源在 `assets/` 或页面同名目录。
///
/// 本适配器保证：
/// - 递归扫描用户选择范围内的全部 .md/.markdown/.html/.htm/.csv；
/// - 页面链接被解析为 `ImportedNoteLink(.internalNote)`，按 32 位页面 ID / 相对路径 / 标题解析到目标笔记；
/// - 指向未导出页面的 Notion URL 保留为 `.externalURL`，无法解析的本地页面链接标记为 `.unresolved` 并告警；
/// - 图片/PDF 等非笔记资源照旧作为附件导入。
public struct NotionExportNoteImportAdapter: NoteImportSourceAdapter {
    public let sourceKind: NoteImportSourceKind = .notionExport
    public var databaseStrategy: NotionDatabaseImportStrategy

    public init(databaseStrategy: NotionDatabaseImportStrategy = .databaseSummary) {
        self.databaseStrategy = databaseStrategy
    }

    public func scan(_ request: NoteImportScanRequest) -> AsyncThrowingStream<ImportedNote, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .utility) {
                do {
                    if request.sourceURL.pathExtension.lowercased() == "zip" {
                        throw NoteImportErrorCode.unsupportedFormat
                    }
                    // 统一规范化根目录，避免 /var 与 /private/var 等符号链接差异导致路径前缀判断不一致。
                    let root = request.sourceURL.resolvingSymlinksInPath().standardizedFileURL
                    let scanned = try Self.notes(root: root, strategy: databaseStrategy, preserveHierarchy: request.options.preserveHierarchy)
                    let notes = scanned.map(\.note)
                    let index = NotionIndex(notes: notes)
                    for (note, rawText) in scanned {
                        try Task.checkCancellation()
                        let format = note.sourceMetadata["notion_format"] ?? "md"
                        let enriched = Self.enrich(note, rawText: rawText, format: format, index: index, root: root)
                        continuation.yield(enriched)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func notes(root: URL, strategy: NotionDatabaseImportStrategy, preserveHierarchy: Bool) throws -> [(note: ImportedNote, rawText: String)] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [(note: ImportedNote, rawText: String)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            guard ["md", "markdown", "html", "htm", "csv"].contains(ext) else { continue }
            if ext == "csv" && strategy == .childPagesOnly { continue }

            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard let text = String(data: data, encoding: .utf8) else { throw NoteImportErrorCode.decodingFailed }
            let relative = relativePath(url, root: root)
            let parsed = parseName(url.deletingPathExtension().lastPathComponent)
            // 树形层级：按导出目录的文件夹链逐段清洗（去掉 " <32位hex>" 后缀），
            // 得到可读的「笔记本/子分类/子页面」路径；不保留层级时为空（扁平导入）。
            let hierarchy: [String]
            if preserveHierarchy {
                hierarchy = relative.split(separator: "/").dropLast().map { Self.parseName(String($0)).title }
            } else {
                hierarchy = []
            }

            if ext == "csv" && strategy == .rowAsNote {
                let rows = parseCSV(text)
                guard let headers = rows.first else { continue }
                for (index, row) in rows.dropFirst().enumerated() {
                    let pairs = zip(headers, row).map { "- **\($0.0):** \($0.1)" }.joined(separator: "\n")
                    let note = make(kind: ext, title: row.first?.nilIfEmpty ?? "\(parsed.title) \(index + 1)", content: pairs, relative: relative + "#row-\(index + 1)", externalID: nil, hierarchy: hierarchy, data: Data(pairs.utf8), root: root, sourceURL: url)
                    result.append((note, pairs))
                }
                continue
            }

            let content = ext.hasPrefix("htm") ? sanitizeHTML(text) : (ext == "csv" ? csvSummary(text, title: parsed.title) : text)
            let note = make(kind: ext, title: parsed.title, content: content, relative: relative, externalID: parsed.id, hierarchy: hierarchy, data: data, root: root, sourceURL: url)
            result.append((note, text))
        }
        return result.sorted { ($0.note.relativePath ?? "") < ($1.note.relativePath ?? "") }
    }

    private static func make(kind: String, title: String, content: String, relative: String, externalID: String?, hierarchy: [String], data: Data, root: URL, sourceURL: URL) -> ImportedNote {
        ImportedNote(
            sourceKind: .notionExport,
            sourceIdentity: externalID ?? relative.precomposedStringWithCanonicalMapping.lowercased(),
            externalID: externalID,
            sourcePath: sourceURL.path,
            relativePath: relative,
            title: title,
            markdownContent: content,
            hierarchy: hierarchy,
            sourceMetadata: ["notion_format": kind],
            rawByteHash: SHA256.hash(data: data).hex,
            normalizedTextHash: SHA256.hash(data: Data(content.replacingOccurrences(of: "\r\n", with: "\n").utf8)).hex
        )
    }

    // MARK: - 链接 / 资源解析

    private struct ParsedReference: Sendable {
        var label: String
        var target: String
        var isImage: Bool
    }

    private static func enrich(_ note: ImportedNote, rawText: String, format: String, index: NotionIndex, root: URL) -> ImportedNote {
        var note = note
        let references = format.hasPrefix("htm") ? htmlReferences(rawText) : markdownReferences(rawText)
        var links: [ImportedNoteLink] = []
        var attachments: [ImportedNoteAttachment] = []
        var diagnostics = note.diagnostics
        var seen = Set<String>()

        for reference in references {
            let target = reference.target
            guard !target.isEmpty else { continue }
            if target.hasPrefix("#") { continue }

            if isExternalURL(target) {
                if let id = notionPageID(target), let resolved = index.byID[NotionIndex.key(id)] {
                    links.append(.init(kind: .internalNote, rawTarget: target, resolvedSourceIdentity: resolved.sourceIdentity, metadata: ["label": reference.label, "notion_url": "true"]))
                } else {
                    links.append(.init(kind: .externalURL, rawTarget: target, metadata: ["label": reference.label]))
                }
                continue
            }

            let cleaned = cleanedLocalTarget(target)
            guard !cleaned.isEmpty else { continue }

            if isNoteTarget(cleaned) {
                let matches = index.resolve(target: cleaned)
                if matches.count == 1 {
                    links.append(.init(kind: .internalNote, rawTarget: target, resolvedSourceIdentity: matches[0].sourceIdentity, metadata: ["label": reference.label, "anchor": target.components(separatedBy: "#").dropFirst().joined(separator: "#")]))
                } else {
                    links.append(.init(kind: .unresolved, rawTarget: target, metadata: ["label": reference.label, "candidate_count": String(matches.count)]))
                    diagnostics.append(.init(severity: .warning, message: matches.isEmpty ? "未解析的 Notion 页面链接：\(target)" : "Notion 页面链接存在多个候选：\(target)"))
                }
                continue
            }

            // 其余本地路径视为附件（图片/PDF 等）
            // 注意：不能对"不存在的目标"直接 resolvingSymlinksInPath()，否则 /private/var 之类的
            // 符号链接不会被解析，导致与规范化后的根目录前缀不一致。先解析已存在的父目录再拼接文件名。
            let decoded = target.removingPercentEncoding ?? target
            let sourceURL = URL(fileURLWithPath: note.sourcePath ?? "")
            let parentResolved = sourceURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            let url = parentResolved.appendingPathComponent(decoded).standardizedFileURL
            let rootURL = root.resolvingSymlinksInPath().standardizedFileURL
            let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
            guard url.path == rootURL.path || url.path.hasPrefix(rootPrefix) else {
                diagnostics.append(.init(code: .unsafePath, severity: .warning, message: "Notion 资源超出导出目录：\(target)"))
                continue
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                diagnostics.append(.init(code: .attachmentMissing, severity: .warning, message: "缺失的 Notion 资源：\(target)"))
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
                diagnostics.append(.init(code: .unsafePath, severity: .warning, message: "Notion 资源不是普通文件：\(target)"))
                continue
            }
            guard seen.insert(url.path).inserted else { continue }
            attachments.append(.init(sourcePath: url.path, displayName: url.lastPathComponent, byteCount: try? AppSessionAttachmentStore.byteCount(forItemAt: url), contentHash: try? AppSessionAttachmentStore.sha256Hex(forItemAt: url), metadata: ["notion_target": target]))
        }

        note.links = links
        note.attachments = attachments
        note.diagnostics = diagnostics
        return note
    }

    private static func markdownReferences(_ text: String) -> [ParsedReference] {
        let regex = try! NSRegularExpression(pattern: "(!?)\\[([^\\]]*)\\]\\(([^)\\n]+)\\)")
        let ns = text as NSString
        var references: [ParsedReference] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let isImage = ns.substring(with: match.range(at: 1)) == "!"
            let label = ns.substring(with: match.range(at: 2))
            let target = markdownTarget(ns.substring(with: match.range(at: 3)))
            references.append(.init(label: label, target: target, isImage: isImage))
        }
        return references
    }

    private static func htmlReferences(_ text: String) -> [ParsedReference] {
        let ns = text as NSString
        var references: [ParsedReference] = []
        let assetRegex = try! NSRegularExpression(pattern: "(?i)<(?:img|video|audio|source|embed|iframe)\\b[^>]*\\bsrc\\s*=\\s*[\"']([^\"']+)[\"']")
        for match in assetRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            references.append(.init(label: "", target: ns.substring(with: match.range(at: 1)), isImage: true))
        }
        let linkRegex = try! NSRegularExpression(pattern: "(?i)<a\\b[^>]*\\bhref\\s*=\\s*[\"']([^\"']+)[\"']")
        for match in linkRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            references.append(.init(label: "", target: ns.substring(with: match.range(at: 1)), isImage: false))
        }
        return references
    }

    private static func isExternalURL(_ target: String) -> Bool {
        if target.hasPrefix("//") { return true }
        return URL(string: target)?.scheme != nil
    }

    private static func notionPageID(_ target: String) -> String? {
        let regex = try! NSRegularExpression(pattern: "[0-9a-fA-F]{32}")
        let ns = target as NSString
        guard let match = regex.firstMatch(in: target, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range)
    }

    private static func cleanedLocalTarget(_ target: String) -> String {
        var value = target.components(separatedBy: "#")[0]
        value = value.removingPercentEncoding ?? value
        value = value.replacingOccurrences(of: "\\", with: "/")
        while value.hasPrefix("./") { value = String(value.dropFirst(2)) }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isNoteTarget(_ cleaned: String) -> Bool {
        ["md", "markdown", "html", "htm"].contains(URL(fileURLWithPath: cleaned).pathExtension.lowercased())
    }

    private static func markdownTarget(_ value: String) -> String {
        var target = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.hasPrefix("<"), let closing = target.firstIndex(of: ">") {
            target = String(target[target.index(after: target.startIndex)..<closing])
        } else if let titleRange = target.range(of: #"\s+["']"#, options: .regularExpression) {
            target = String(target[..<titleRange.lowerBound])
        }
        return target.components(separatedBy: "#")[0]
    }

    // MARK: - 页面索引

    private struct NotionIndex {
        var byID: [String: ImportedNote] = [:]
        var byPath: [String: ImportedNote] = [:]
        var byTitle: [String: [ImportedNote]] = [:]

        init(notes: [ImportedNote]) {
            for note in notes {
                if let id = note.externalID { byID[Self.key(id)] = note }
                if let relative = note.relativePath {
                    let pathKey = Self.key(relative)
                    if byPath[pathKey] == nil { byPath[pathKey] = note }
                    let base = Self.baseName(relative)
                    if !base.isEmpty { byTitle[Self.key(base), default: []].append(note) }
                }
                let titleKey = Self.key(note.title)
                if !titleKey.isEmpty { byTitle[titleKey, default: []].append(note) }
            }
        }

        func resolve(target: String) -> [ImportedNote] {
            let cleaned = NotionExportNoteImportAdapter.cleanedLocalTarget(target)
            let pathKey = Self.key(cleaned)
            if let exact = byPath[pathKey] { return [exact] }
            let withoutExtension = Self.key(Self.deletingNoteExtension(cleaned))
            if let exact = byPath[withoutExtension] { return [exact] }
            let base = Self.baseName(cleaned)
            if let id = NotionExportNoteImportAdapter.notionPageID(base), let note = byID[Self.key(id)] { return [note] }
            if let matches = byTitle[Self.key(base)], !matches.isEmpty { return matches }
            let stripped = Self.stripIDHash(base)
            if let matches = byTitle[Self.key(stripped)], !matches.isEmpty { return matches }
            return []
        }

        static func key(_ value: String) -> String {
            value.components(separatedBy: "#")[0]
                .replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
        }

        private static func baseName(_ value: String) -> String {
            let last = URL(fileURLWithPath: value.components(separatedBy: "#")[0]).lastPathComponent
            return deletingNoteExtension(last)
        }

        private static func deletingNoteExtension(_ value: String) -> String {
            let ext = URL(fileURLWithPath: value).pathExtension.lowercased()
            return ["md", "markdown", "html", "htm"].contains(ext) ? String(value.dropLast(ext.count + 1)) : value
        }

        private static func stripIDHash(_ value: String) -> String {
            let regex = try! NSRegularExpression(pattern: "^(.*) ([0-9a-fA-F]{32})$")
            let ns = value as NSString
            guard let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: ns.length)) else { return value }
            return ns.substring(with: match.range(at: 1))
        }
    }

    // MARK: - 基础解析

    private static func parseName(_ value: String) -> (title: String, id: String?) {
        let regex = try! NSRegularExpression(pattern: "^(.*) ([0-9a-fA-F]{32})$")
        let ns = value as NSString
        guard let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: ns.length)) else { return (value, nil) }
        return (ns.substring(with: match.range(at: 1)), ns.substring(with: match.range(at: 2)))
    }

    private static func sanitizeHTML(_ html: String) -> String {
        var value = html
            .replacingOccurrences(of: "(?is)<script.*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<style.*?</style>", with: "", options: .regularExpression)
        value = value
            .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</(p|div|li|h[1-6]|tr)>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeHTMLEntities(value)
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func csvSummary(_ csv: String, title: String) -> String {
        let rows = parseCSV(csv)
        guard let headers = rows.first else { return "# \(title)\n\n数据库导出，共 0 行。" }
        let header = "| " + headers.joined(separator: " | ") + " |"
        let separator = "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |"
        let body = rows.dropFirst().prefix(20).map { "| " + $0.joined(separator: " | ") + " |" }.joined(separator: "\n")
        return "# \(title)\n\n数据库导出，共 \(max(rows.count - 1, 0)) 行。\n\n\(header)\n\(separator)\n\(body)"
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let character = chars[index]
            if character == "\"" {
                if quoted && index + 1 < chars.count && chars[index + 1] == "\"" { field.append("\""); index += 1 }
                else { quoted.toggle() }
            } else if character == "," && !quoted {
                row.append(field); field = ""
            } else if (character == "\n" || character == "\r") && !quoted {
                if character == "\r" && index + 1 < chars.count && chars[index + 1] == "\n" { index += 1 }
                row.append(field); rows.append(row); row = []; field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let urlPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        return String(urlPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private extension Digest { var hex: String { map { String(format: "%02x", $0) }.joined() } }
private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
