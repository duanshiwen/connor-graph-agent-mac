import Foundation
import ConnorGraphCore

public struct ObsidianVaultNoteImportAdapter: NoteImportSourceAdapter {
    public let sourceKind: NoteImportSourceKind = .obsidianVault
    private let markdown: MarkdownFolderNoteImportAdapter
    public init(decoder: TextDecodingService = .init()) { markdown = .init(decoder: decoder) }

    public func scan(_ request: NoteImportScanRequest) -> AsyncThrowingStream<ImportedNote, Error> {
        AsyncThrowingStream { continuation in
            Task.detached(priority: .utility) {
                do {
                    var notes: [ImportedNote] = []
                    for try await note in markdown.scan(.init(sourceID: request.sourceID, sourceURL: request.sourceURL, kind: .obsidianVault, options: request.options)) { notes.append(note) }
                    let index = VaultIndex(notes: notes)
                    let assetIndex = AssetIndex(root: request.sourceURL)
                    for var note in notes {
                        let aliases = Self.aliases(in: note.markdownContent)
                        note.sourceMetadata["obsidian_aliases"] = aliases.joined(separator: "|")
                        let parsed = Self.parseLinks(in: note.markdownContent, current: note, index: index, assetIndex: assetIndex)
                        note.links = parsed.links; note.attachments = parsed.attachments; note.diagnostics.append(contentsOf: parsed.diagnostics)
                        continuation.yield(note)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    private struct VaultIndex {
        var byPath: [String: ImportedNote] = [:]; var byName: [String: [ImportedNote]] = [:]; var byAlias: [String: [ImportedNote]] = [:]
        init(notes: [ImportedNote]) { for note in notes { if let path = note.relativePath { byPath[Self.key(path.deletingMarkdownExtension)] = note }; byName[Self.key((note.relativePath ?? note.title).lastPathComponent.deletingMarkdownExtension), default: []].append(note); for alias in ObsidianVaultNoteImportAdapter.aliases(in: note.markdownContent) { byAlias[Self.key(alias), default: []].append(note) } } }
        func resolve(_ target: String) -> [ImportedNote] { let base = target.components(separatedBy: "#")[0]; let key = Self.key(base.deletingMarkdownExtension); if let exact = byPath[key] { return [exact] }; if let alias = byAlias[key], !alias.isEmpty { return alias }; return byName[Self.key(base.lastPathComponent.deletingMarkdownExtension)] ?? [] }
        static func key(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }

    private static func aliases(in markdown: String) -> [String] {
        guard markdown.hasPrefix("---"), let end = markdown.dropFirst(3).range(of: "\n---") else { return [] }
        let frontmatter = String(markdown[markdown.index(markdown.startIndex, offsetBy: 3)..<end.lowerBound])
        let lines = frontmatter.components(separatedBy: .newlines); var values: [String] = []; var collecting = false
        for line in lines { let trimmed = line.trimmingCharacters(in: .whitespaces); if trimmed.lowercased().hasPrefix("aliases:") { collecting = true; let value = trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces); if value.hasPrefix("[") { values += value.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).components(separatedBy: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }; collecting = false } } else if collecting && trimmed.hasPrefix("-") { values.append(trimmed.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))) } else if collecting && !trimmed.isEmpty { collecting = false } }
        return values.filter { !$0.isEmpty }
    }

    private final class AssetIndex: @unchecked Sendable {
        private let root: URL
        private var byRelativePath: [String: URL] = [:]
        private var byBasename: [String: [URL]] = [:]
        private var metadataCache: [String: (byteCount: Int64?, contentHash: String?)] = [:]

        init(root: URL) {
            self.root = root.standardizedFileURL
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let standardized = url.standardizedFileURL
                let relative = String(standardized.path.dropFirst(self.root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                byRelativePath[Self.key(relative)] = standardized
                byBasename[Self.key(standardized.lastPathComponent), default: []].append(standardized)
            }
        }

        func candidates(target: String, current: ImportedNote) -> [URL] {
            let clean = target.components(separatedBy: "#")[0]
            var candidates: [URL] = []
            if let relative = current.relativePath {
                let parent = (relative as NSString).deletingLastPathComponent
                let path = (parent as NSString).appendingPathComponent(clean)
                if let exact = byRelativePath[Self.key(path)] { return [exact] }
            }
            if let exact = byRelativePath[Self.key(clean)] { return [exact] }
            candidates.append(contentsOf: byBasename[Self.key(URL(fileURLWithPath: clean).lastPathComponent)] ?? [])
            var seen = Set<String>()
            return candidates.filter { seen.insert($0.path).inserted }
        }

        func metadata(for url: URL) -> (byteCount: Int64?, contentHash: String?) {
            if let cached = metadataCache[url.path] { return cached }
            let value = (
                try? AppSessionAttachmentStore.byteCount(forItemAt: url),
                try? AppSessionAttachmentStore.sha256Hex(forItemAt: url)
            )
            metadataCache[url.path] = value
            return value
        }

        private static func key(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
        }
    }

    private static func parseLinks(in text: String, current: ImportedNote, index: VaultIndex, assetIndex: AssetIndex) -> (links: [ImportedNoteLink], attachments: [ImportedNoteAttachment], diagnostics: [NoteImportDiagnostic]) {
        let regex = try! NSRegularExpression(pattern: "(!?)\\[\\[([^\\]]+)\\]\\]"); let ns = text as NSString; var links: [ImportedNoteLink] = []; var attachments: [ImportedNoteAttachment] = []; var diagnostics: [NoteImportDiagnostic] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) { let embed = ns.substring(with: match.range(at: 1)) == "!"; let expression = ns.substring(with: match.range(at: 2)); let target = expression.components(separatedBy: "|")[0]; let extensionName = URL(fileURLWithPath: target.components(separatedBy: "#")[0]).pathExtension.lowercased(); let isAsset = embed && !extensionName.isEmpty && !["md", "markdown"].contains(extensionName)
            if isAsset { let candidates = assetIndex.candidates(target: target, current: current); if candidates.count == 1 { let url = candidates[0]; let metadata = assetIndex.metadata(for: url); attachments.append(.init(sourcePath: url.path, displayName: url.lastPathComponent, byteCount: metadata.byteCount, contentHash: metadata.contentHash, metadata: ["obsidian_embed": expression])) } else { diagnostics.append(.init(code: .attachmentMissing, severity: .warning, message: candidates.isEmpty ? "Missing Obsidian attachment: \(target)" : "Ambiguous Obsidian attachment: \(target)")) }; continue }
            let matches = index.resolve(target); if matches.count == 1 { links.append(.init(kind: .internalNote, rawTarget: expression, resolvedSourceIdentity: matches[0].sourceIdentity, metadata: ["embed": String(embed), "anchor": target.components(separatedBy: "#").dropFirst().joined(separator: "#")])) } else { links.append(.init(kind: .unresolved, rawTarget: expression, metadata: ["candidate_count": String(matches.count), "embed": String(embed)])); diagnostics.append(.init(severity: .warning, message: matches.isEmpty ? "Unresolved Obsidian link: \(target)" : "Ambiguous Obsidian link: \(target)")) }
        }
        return (links, attachments, diagnostics)
    }

}

private extension String { var deletingMarkdownExtension: String { let ext = URL(fileURLWithPath: self).pathExtension.lowercased(); return ["md", "markdown"].contains(ext) ? String(dropLast(ext.count + 1)) : self }; var lastPathComponent: String { URL(fileURLWithPath: self).lastPathComponent } }
