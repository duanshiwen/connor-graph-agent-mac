import Foundation
import ConnorGraphStore

public struct LegacyImportWarning: Codable, Sendable, Equatable {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public struct LegacyDirectoryImportReport: Codable, Sendable, Equatable {
    public var scannedFiles: Int
    public var importedNodes: Int
    public var importedEdges: Int
    public var skippedFiles: Int
    public var warnings: [LegacyImportWarning]

    public init(
        scannedFiles: Int = 0,
        importedNodes: Int = 0,
        importedEdges: Int = 0,
        skippedFiles: Int = 0,
        warnings: [LegacyImportWarning] = []
    ) {
        self.scannedFiles = scannedFiles
        self.importedNodes = importedNodes
        self.importedEdges = importedEdges
        self.skippedFiles = skippedFiles
        self.warnings = warnings
    }
}

public struct LegacyKnowledgeDirectoryImporter: Sendable {
    private let store: SQLiteGraphStore
    private let parser: FrontmatterParser
    private let importer: LegacyMarkdownImporter

    public init(
        store: SQLiteGraphStore,
        parser: FrontmatterParser = FrontmatterParser(),
        importer: LegacyMarkdownImporter = LegacyMarkdownImporter()
    ) {
        self.store = store
        self.parser = parser
        self.importer = importer
    }

    public func importDirectory(_ root: URL) throws -> LegacyDirectoryImportReport {
        let markdownFiles = try markdownFilesUnder(root)
        var report = LegacyDirectoryImportReport(scannedFiles: markdownFiles.count)

        for file in markdownFiles {
            do {
                let content = try String(contentsOf: file, encoding: .utf8)
                let relativePath = Self.relativePath(file, under: root)
                let document = try parser.parse(content, sourcePath: relativePath)
                let result = try importer.importDocument(document)
                for node in result.nodes {
                    try store.upsert(node: node)
                }
                for edge in result.edges {
                    try store.upsert(edge: edge)
                }
                report.importedNodes += result.nodes.count
                report.importedEdges += result.edges.count
            } catch {
                report.skippedFiles += 1
                report.warnings.append(LegacyImportWarning(path: file.path, message: String(describing: error)))
            }
        }

        return report
    }

    private func markdownFilesUnder(_ root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            guard url.pathExtension.lowercased() == "md" else { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func relativePath(_ file: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let filePath = file.standardizedFileURL.path
        let prefix = "/\(rootPath)/"
        if filePath.hasPrefix(prefix) {
            return String(filePath.dropFirst(prefix.count))
        }
        return file.lastPathComponent
    }
}
