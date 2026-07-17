import Foundation
import CryptoKit
import ConnorGraphCore

public struct MarkdownFolderNoteImportAdapter: NoteImportSourceAdapter, Sendable {
    public let sourceKind: NoteImportSourceKind
    private let decoder: TextDecodingService

    public init(sourceKind: NoteImportSourceKind = .markdownFolder, decoder: TextDecodingService = .init()) {
        self.sourceKind = sourceKind; self.decoder = decoder
    }

    public func scan(_ request: NoteImportScanRequest) -> AsyncThrowingStream<ImportedNote, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .utility) {
                do {
                    for url in try files(root: request.sourceURL, recursively: request.options.recursivelyScan, ignores: request.options.ignoredPathPatterns) {
                        try Task.checkCancellation()
                        continuation.yield(try parse(url: url, root: request.sourceURL, request: request))
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func files(root: URL, recursively: Bool, ignores: [String]) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants, recursively ? [] : .skipsSubdirectoryDescendants].reduce([]) { $0.union($1) }, errorHandler: { _, _ in true }) else { throw NoteImportErrorCode.sourceUnavailable }
        var output: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { if values.isDirectory == true { enumerator.skipDescendants() }; continue }
            let relative = relativePath(url, root: root)
            if ignores.contains(where: { relative.localizedStandardContains($0) }) { if values.isDirectory == true { enumerator.skipDescendants() }; continue }
            guard values.isRegularFile == true, ["md", "markdown"].contains(url.pathExtension.lowercased()) else { continue }
            output.append(url)
        }
        return output.sorted { relativePath($0, root: root) < relativePath($1, root: root) }
    }

    private func parse(url: URL, root: URL, request: NoteImportScanRequest) throws -> ImportedNote {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let decoded = try decoder.decode(.init(data: data, userSelectedEncoding: request.options.defaultEncodingName, allowLossy: request.options.allowLossyDecoding))
        let relative = relativePath(url, root: root)
        let normalized = normalize(decoded.text)
        let metadata = frontmatter(decoded.text)
        let title = metadata["title"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            ?? firstHeading(decoded.text)
            ?? url.deletingPathExtension().lastPathComponent
        let hierarchy = request.options.preserveHierarchy
            ? relative.split(separator: "/").dropLast().map(String.init)
            : []
        var sourceMetadata = metadata
        sourceMetadata["encoding"] = decoded.encodingName
        sourceMetadata["encoding_confidence"] = decoded.confidence.rawValue
        sourceMetadata["decoder_version"] = TextDecodingService.decoderVersion
        sourceMetadata["had_bom"] = String(decoded.hadBOM)
        sourceMetadata["was_lossy"] = String(decoded.wasLossy)
        return ImportedNote(sourceKind: request.kind, sourceIdentity: "\(request.sourceID):\(relative.precomposedStringWithCanonicalMapping.lowercased())", sourcePath: url.path, relativePath: relative, title: title, markdownContent: decoded.text, hierarchy: hierarchy, sourceMetadata: sourceMetadata, rawByteHash: hash(data), normalizedTextHash: hash(Data(normalized.utf8)), diagnostics: diagnostics(decoded))
    }

    private func diagnostics(_ result: TextDecodingResult) -> [NoteImportDiagnostic] {
        var values: [NoteImportDiagnostic] = []
        if result.confidence == .low || result.confidence == .ambiguous { values.append(.init(code: .decodingAmbiguous, severity: .warning, message: "文本编码需要确认", metadata: ["encoding": result.encodingName, "candidates": result.candidateEncodingNames.joined(separator: ",")])) }
        if result.wasLossy { values.append(.init(code: .lossyDecodingRequiresApproval, severity: .warning, message: "文本使用了损失性解码")) }
        return values
    }

    private func frontmatter(_ text: String) -> [String: String] {
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var result: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    private func firstHeading(_ text: String) -> String? { text.components(separatedBy: .newlines).first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 } }
    private func normalize(_ text: String) -> String { text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").precomposedStringWithCanonicalMapping }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func relativePath(_ url: URL, root: URL) -> String { String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
}
