import Foundation
import CryptoKit
import ConnorGraphCore

public enum NotionDatabaseImportStrategy: String, Sendable, Codable {
    case childPagesOnly = "child_pages_only"
    case databaseSummary = "database_summary"
    case rowAsNote = "row_as_note"
}

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
                    for note in try Self.notes(root: request.sourceURL, strategy: databaseStrategy, preserveHierarchy: request.options.preserveHierarchy) {
                        try Task.checkCancellation()
                        continuation.yield(note)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func notes(root: URL, strategy: NotionDatabaseImportStrategy, preserveHierarchy: Bool) throws -> [ImportedNote] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [ImportedNote] = []
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
            let hierarchy = preserveHierarchy ? relative.split(separator: "/").dropLast().map(String.init) : []

            if ext == "csv" && strategy == .rowAsNote {
                let rows = parseCSV(text)
                guard let headers = rows.first else { continue }
                for (index, row) in rows.dropFirst().enumerated() {
                    let pairs = zip(headers, row).map { "- **\($0.0):** \($0.1)" }.joined(separator: "\n")
                    result.append(make(kind: ext, title: row.first?.nilIfEmpty ?? "\(parsed.title) \(index + 1)", content: pairs, relative: relative + "#row-\(index + 1)", externalID: nil, hierarchy: hierarchy, data: Data(pairs.utf8), root: root, sourceURL: url))
                }
                continue
            }

            let content = ext.hasPrefix("htm") ? sanitizeHTML(text) : (ext == "csv" ? csvSummary(text, title: parsed.title) : text)
            result.append(make(kind: ext, title: parsed.title, content: content, relative: relative, externalID: parsed.id, hierarchy: hierarchy, data: data, root: root, sourceURL: url, originalText: text))
        }
        return result.sorted { ($0.relativePath ?? "") < ($1.relativePath ?? "") }
    }

    private static func make(kind: String, title: String, content: String, relative: String, externalID: String?, hierarchy: [String], data: Data, root: URL, sourceURL: URL, originalText: String? = nil) -> ImportedNote {
        let references = assetLinks(originalText ?? content, html: kind.hasPrefix("htm"))
        let rootURL = root.resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        var diagnostics: [NoteImportDiagnostic] = []
        var seen = Set<String>()
        let assets = references.compactMap { raw -> ImportedNoteAttachment? in
            guard !raw.isEmpty, !raw.hasPrefix("#"), URL(string: raw)?.scheme == nil else { return nil }
            let decoded = raw.removingPercentEncoding ?? raw
            let url = sourceURL.deletingLastPathComponent().appendingPathComponent(decoded).resolvingSymlinksInPath().standardizedFileURL
            guard url.path == rootURL.path || url.path.hasPrefix(rootPrefix) else {
                diagnostics.append(.init(code: .unsafePath, severity: .warning, message: "Notion resource escapes the export folder: \(raw)"))
                return nil
            }
            guard FileManager.default.fileExists(atPath: url.path), !["md", "markdown", "html", "htm", "csv"].contains(url.pathExtension.lowercased()) else { return nil }
            guard seen.insert(url.path).inserted else { return nil }
            return .init(sourcePath: url.path, displayName: url.lastPathComponent, byteCount: try? AppSessionAttachmentStore.byteCount(forItemAt: url), contentHash: try? AppSessionAttachmentStore.sha256Hex(forItemAt: url), metadata: ["notion_target": raw])
        }
        return ImportedNote(sourceKind: .notionExport, sourceIdentity: externalID ?? relative.precomposedStringWithCanonicalMapping.lowercased(), externalID: externalID, sourcePath: sourceURL.path, relativePath: relative, title: title, markdownContent: content, hierarchy: hierarchy, attachments: assets, sourceMetadata: ["notion_format": kind], rawByteHash: SHA256.hash(data: data).hex, normalizedTextHash: SHA256.hash(data: Data(content.replacingOccurrences(of: "\r\n", with: "\n").utf8)).hex, diagnostics: diagnostics)
    }

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

    private static func assetLinks(_ text: String, html: Bool) -> [String] {
        var values: [String] = []
        let markdownRegex = try! NSRegularExpression(pattern: "!?\\[[^\\]]*\\]\\(([^)\\n]+)\\)")
        let ns = text as NSString
        values += markdownRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1)).components(separatedBy: "#")[0]
        }
        if html {
            let htmlRegex = try! NSRegularExpression(pattern: "(?i)(?:src|href)\\s*=\\s*[\"']([^\"'#]+)[\"']")
            values += htmlRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
                ns.substring(with: $0.range(at: 1))
            }
        }
        return values
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
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private extension Digest { var hex: String { map { String(format: "%02x", $0) }.joined() } }
private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
