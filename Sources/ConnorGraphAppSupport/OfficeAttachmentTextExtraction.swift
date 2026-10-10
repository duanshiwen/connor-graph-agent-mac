import Foundation
import ConnorGraphCore

/// Local OOXML extraction; reuses the bounded archive backend on both Apple platforms.
public enum OfficeAttachmentTextExtraction {
    public static func supports(fileExtension: String) -> Bool {
        ["doc", "xls", "ppt", "docx", "xlsx", "pptx"].contains(fileExtension.lowercased())
    }

    public static func extract(fileURL: URL, attachmentID: String = "") throws -> AttachmentExtractionResult {
        let started = Date()
        func result(_ status: AgentAttachmentExtractionStatus, text: String? = nil, error: String? = nil) -> AttachmentExtractionResult {
            AttachmentExtractionResult(
                report: AgentAttachmentExtractionReport(
                    attachmentID: attachmentID, engine: .builtinOfficeText, status: status,
                    capabilitiesUsed: [LegacyOfficeText.supports(fileURL.pathExtension) ? "ole2-text" : "ooxml-text"], errors: error.map { [$0] } ?? [],
                    startedAt: started, completedAt: Date()),
                extractedMarkdown: text, previewText: text.map { String($0.prefix(240)) })
        }
        guard supports(fileExtension: fileURL.pathExtension) else { return result(.unsupported) }
        guard (try fileURL.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 <= 50_000_000 else {
            return result(.skippedOversize)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("connor-office-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            if LegacyOfficeText.supports(fileURL.pathExtension) {
                let text = try LegacyOfficeText.extract(Data(contentsOf: fileURL), fileExtension: fileURL.pathExtension)
                return text.isEmpty ? result(.unsupported) : result(.extracted, text: "# Extracted attachment: \(fileURL.lastPathComponent)\n\n" + text)
            }
            let extractor = SafeArchiveExtractor(backend: SystemZipArchiveBackend(), limits: .init(
                maxEntries: 4096, maxEntryBytes: 8_000_000, maxTotalBytes: 64_000_000))
            let entries = try extractor.extract(fileURL, to: root)
            let ext = fileURL.pathExtension.lowercased()
            let sharedURL = root.appendingPathComponent("xl/sharedStrings.xml")
            let shared = ext == "xlsx" && FileManager.default.fileExists(atPath: sharedURL.path)
                ? try parse(sharedURL).descendants("si").map { $0.descendants("t").map(\.text).joined() } : []
            let selected = entries.filter { !$0.isDirectory && accepts($0.path, ext: ext) }
                .sorted { $0.path.compare($1.path, options: .numeric) == .orderedAscending }
            var sections: [String] = []
            for entry in selected {
                let node = try parse(root.appendingPathComponent(entry.path))
                let body: String
                if ext == "xlsx" {
                    body = node.descendants("row").map { row in
                        row.descendants("c").map { cell in
                            let raw = cell.descendants("v").first?.text ?? ""
                            let value: String
                            if cell.attributes["t"] == "s", let index = Int(raw), shared.indices.contains(index) {
                                value = shared[index]
                            } else if cell.attributes["t"] == "inlineStr" {
                                value = cell.descendants("t").map(\.text).joined()
                            } else { value = raw }
                            return "\(cell.attributes["r"] ?? "?")=\(value)"
                        }.joined(separator: "\t")
                    }.joined(separator: "\n")
                } else {
                    body = node.descendants("p").map { $0.descendants("t").map(\.text).joined() }
                        .filter { !$0.isEmpty }.joined(separator: "\n")
                }
                if !body.isEmpty { sections.append("## \(entry.path)\n\n\(body)") }
            }
            guard !sections.isEmpty else { return result(.unsupported) }
            return result(.extracted, text: "# Extracted attachment: \(fileURL.lastPathComponent)\n\n" + sections.joined(separator: "\n\n"))
        } catch {
            return result(.failed, error: "无法解析 Office 文档：\(error.localizedDescription)")
        }
    }

    private static func accepts(_ path: String, ext: String) -> Bool {
        guard path.hasSuffix(".xml") else { return false }
        switch ext {
        case "docx": return path == "word/document.xml" || path.hasPrefix("word/header") || path.hasPrefix("word/footer")
        case "xlsx": return path.hasPrefix("xl/worksheets/sheet")
        case "pptx": return path.hasPrefix("ppt/slides/slide") || path.hasPrefix("ppt/notesSlides/notesSlide")
        default: return false
        }
    }

    private static func parse(_ url: URL) throws -> OfficeXMLNode {
        let data = try Data(contentsOf: url)
        // Reject DTDs before parsing; OOXML has no need for entity declarations.
        guard let xml = String(data: data, encoding: .utf8), !xml.contains("<!DOCTYPE"), !xml.contains("<!ENTITY") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        let collector = OfficeXMLCollector()
        parser.delegate = collector
        guard parser.parse(), let root = collector.root else { throw CocoaError(.fileReadCorruptFile) }
        return root
    }
}

private final class OfficeXMLNode {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [OfficeXMLNode] = []
    init(_ name: String, attributes: [String: String]) { self.name = name; self.attributes = attributes }
    func descendants(_ name: String) -> [OfficeXMLNode] {
        children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
    }
}

private final class OfficeXMLCollector: NSObject, XMLParserDelegate {
    var root: OfficeXMLNode?
    private var stack: [OfficeXMLNode] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard stack.count < 128 else { parser.abortParsing(); return }
        let node = OfficeXMLNode(elementName, attributes: attributes)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) { _ = stack.popLast() }
}
