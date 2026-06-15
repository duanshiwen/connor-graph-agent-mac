import Foundation
import ConnorGraphCore

public enum AgentMarkdownCompiledBlockKind: String, Sendable, Equatable {
    case heading
    case paragraph
    case unorderedItem
    case orderedItem
    case taskItem
    case quote
    case code
    case table
    case horizontalRule
    case spacer
}

public enum AgentMarkdownCompiledBlockContent: Sendable, Equatable {
    case heading(level: Int, text: String, inline: AttributedString)
    case paragraph(text: String, inline: AttributedString)
    case unorderedItem(text: String, inline: AttributedString)
    case orderedItem(number: String, text: String, inline: AttributedString)
    case taskItem(isCompleted: Bool, text: String, inline: AttributedString)
    case quote(text: String, inline: AttributedString)
    case code(language: String?, text: String)
    case table(AgentMarkdownTable)
    case horizontalRule
    case spacer

    public var kind: AgentMarkdownCompiledBlockKind {
        switch self {
        case .heading: return .heading
        case .paragraph: return .paragraph
        case .unorderedItem: return .unorderedItem
        case .orderedItem: return .orderedItem
        case .taskItem: return .taskItem
        case .quote: return .quote
        case .code: return .code
        case .table: return .table
        case .horizontalRule: return .horizontalRule
        case .spacer: return .spacer
        }
    }
}

public struct AgentMarkdownCompiledBlock: Identifiable, Sendable, Equatable {
    public var id: String
    public var sourceIndex: Int
    public var content: AgentMarkdownCompiledBlockContent

    public var kind: AgentMarkdownCompiledBlockKind { content.kind }

    public init(id: String, sourceIndex: Int, content: AgentMarkdownCompiledBlockContent) {
        self.id = id
        self.sourceIndex = sourceIndex
        self.content = content
    }
}

public struct AgentMarkdownCompiledDocument: Identifiable, Sendable, Equatable {
    public var id: String
    public var source: String
    public var blocks: [AgentMarkdownCompiledBlock]

    public init(id: String, source: String, blocks: [AgentMarkdownCompiledBlock]) {
        self.id = id
        self.source = source
        self.blocks = blocks
    }
}

public struct AgentMarkdownDocumentCompiler: Sendable {
    public static let parserVersion = 1
    public static let rendererVersion = 1

    private let parser: AgentMarkdownBlockParser

    public init(parser: AgentMarkdownBlockParser = AgentMarkdownBlockParser()) {
        self.parser = parser
    }

    public func compile(_ markdown: String) -> AgentMarkdownCompiledDocument {
        compile(source: markdown, blocks: parser.parse(markdown))
    }

    public func compile(source markdown: String, blocks: [AgentMarkdownBlock]) -> AgentMarkdownCompiledDocument {
        let compiledBlocks = blocks.enumerated().map { index, block in
            compile(block, at: index)
        }
        return AgentMarkdownCompiledDocument(
            id: "document-\(Self.stableFingerprint(markdown))",
            source: markdown,
            blocks: compiledBlocks
        )
    }

    private func compile(_ block: AgentMarkdownBlock, at index: Int) -> AgentMarkdownCompiledBlock {
        let content: AgentMarkdownCompiledBlockContent
        switch block {
        case .heading(let level, let text):
            content = .heading(level: level, text: text, inline: renderInline(text))
        case .paragraph(let text):
            content = .paragraph(text: text, inline: renderInline(text))
        case .unorderedItem(let text):
            content = .unorderedItem(text: text, inline: renderInline(text))
        case .orderedItem(let number, let text):
            content = .orderedItem(number: number, text: text, inline: renderInline(text))
        case .taskItem(let isCompleted, let text):
            content = .taskItem(isCompleted: isCompleted, text: text, inline: renderInline(text))
        case .quote(let text):
            content = .quote(text: text, inline: renderInline(text))
        case .code(let language, let text):
            content = .code(language: language, text: text)
        case .table(let table):
            content = .table(table)
        case .horizontalRule:
            content = .horizontalRule
        case .spacer:
            content = .spacer
        }
        return AgentMarkdownCompiledBlock(
            id: "block-\(index)-\(content.kind.rawValue)-\(Self.stableFingerprint(blockIDSource(for: block)))",
            sourceIndex: index,
            content: content
        )
    }

    private func renderInline(_ markdown: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(markdown)
    }

    private func blockIDSource(for block: AgentMarkdownBlock) -> String {
        switch block {
        case .heading(let level, let text): return "heading|\(level)|\(text)"
        case .paragraph(let text): return "paragraph|\(text)"
        case .unorderedItem(let text): return "unordered|\(text)"
        case .orderedItem(let number, let text): return "ordered|\(number)|\(text)"
        case .taskItem(let isCompleted, let text): return "task|\(isCompleted)|\(text)"
        case .quote(let text): return "quote|\(text)"
        case .code(let language, let text): return "code|\(language ?? "")|\(text)"
        case .table(let table): return "table|\(table.headers.joined(separator: "|"))|\(table.rows.flatMap { $0 }.joined(separator: "|"))"
        case .horizontalRule: return "horizontal-rule"
        case .spacer: return "spacer"
        }
    }

    public static func stableFingerprint(_ string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

public struct AgentMarkdownCompiledRenderWindow: Sendable, Equatable {
    public var blocks: [AgentMarkdownCompiledBlock]
    public var omittedBlockCount: Int

    public init(blocks: [AgentMarkdownCompiledBlock], omittedBlockCount: Int) {
        self.blocks = blocks
        self.omittedBlockCount = omittedBlockCount
    }
}

public struct AgentMarkdownCompiledRenderWindowPolicy: Sendable {
    public init() {}

    public func window(
        for document: AgentMarkdownCompiledDocument,
        maxRenderedBlocks: Int?
    ) -> AgentMarkdownCompiledRenderWindow {
        guard let maxRenderedBlocks else {
            return AgentMarkdownCompiledRenderWindow(blocks: document.blocks, omittedBlockCount: 0)
        }
        let clampedLimit = max(0, maxRenderedBlocks)
        guard document.blocks.count > clampedLimit else {
            return AgentMarkdownCompiledRenderWindow(blocks: document.blocks, omittedBlockCount: 0)
        }
        return AgentMarkdownCompiledRenderWindow(
            blocks: Array(document.blocks.prefix(clampedLimit)),
            omittedBlockCount: document.blocks.count - clampedLimit
        )
    }
}

public final class AgentMarkdownCompiledDocumentCache: @unchecked Sendable {
    private var documents: [String: AgentMarkdownCompiledDocument] = [:]
    private var insertionOrder: [String] = []
    private let limit: Int
    private let lock = NSLock()

    public init(limit: Int = 600) {
        self.limit = max(1, limit)
    }

    public func document(
        for markdown: String,
        loadBlocks: ((String) -> [AgentMarkdownBlock]?)? = nil,
        persistBlocks: ((String, [AgentMarkdownBlock]) -> Void)? = nil,
        compile: (String, [AgentMarkdownBlock]?) -> AgentMarkdownCompiledDocument = { source, cachedBlocks in
            if let cachedBlocks {
                return AgentMarkdownDocumentCompiler().compile(source: source, blocks: cachedBlocks)
            }
            return AgentMarkdownDocumentCompiler().compile(source)
        }
    ) -> AgentMarkdownCompiledDocument {
        lock.lock()
        if let cached = documents[markdown] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let cachedBlocks = loadBlocks?(markdown)
        let compiled = compile(markdown, cachedBlocks)
        if cachedBlocks == nil {
            persistBlocks?(markdown, AgentMarkdownBlockParser().parse(markdown))
        }

        lock.lock()
        if let cached = documents[markdown] {
            lock.unlock()
            return cached
        }
        if documents.count >= limit, let oldest = insertionOrder.first {
            documents.removeValue(forKey: oldest)
            insertionOrder.removeFirst()
        }
        documents[markdown] = compiled
        insertionOrder.append(markdown)
        lock.unlock()
        return compiled
    }

    public func removeAll(keepingCapacity: Bool = true) {
        lock.lock()
        documents.removeAll(keepingCapacity: keepingCapacity)
        insertionOrder.removeAll(keepingCapacity: keepingCapacity)
        lock.unlock()
    }
}

public struct AgentMarkdownRenderCacheFile: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var parserVersion: Int
    public var rendererVersion: Int
    public var sessionID: String
    public var messageID: String
    public var contentHash: String
    public var blocks: [AgentMarkdownBlock]
    public var createdAt: Date

    public init(
        schemaVersion: Int = 1,
        parserVersion: Int = AgentMarkdownDocumentCompiler.parserVersion,
        rendererVersion: Int = AgentMarkdownDocumentCompiler.rendererVersion,
        sessionID: String,
        messageID: String,
        contentHash: String,
        blocks: [AgentMarkdownBlock],
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.parserVersion = parserVersion
        self.rendererVersion = rendererVersion
        self.sessionID = sessionID
        self.messageID = messageID
        self.contentHash = contentHash
        self.blocks = blocks
        self.createdAt = createdAt
    }
}

public struct AgentMarkdownRenderCacheStore: @unchecked Sendable {
    public var storagePaths: AppStoragePaths
    public var fileManager: FileManager

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default) {
        self.storagePaths = storagePaths
        self.fileManager = fileManager
    }

    public func loadBlocks(sessionID: String, messageID: String, content: String) throws -> [AgentMarkdownBlock]? {
        let url = try cacheURL(sessionID: sessionID, messageID: messageID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let file = try decoder().decode(AgentMarkdownRenderCacheFile.self, from: data)
        guard file.schemaVersion == 1,
              file.parserVersion == AgentMarkdownDocumentCompiler.parserVersion,
              file.rendererVersion == AgentMarkdownDocumentCompiler.rendererVersion,
              file.sessionID == sessionID,
              file.messageID == messageID,
              file.contentHash == Self.contentHash(content) else {
            return nil
        }
        return file.blocks
    }

    public func saveBlocks(sessionID: String, messageID: String, content: String, blocks: [AgentMarkdownBlock], createdAt: Date = Date()) throws {
        let url = try cacheURL(sessionID: sessionID, messageID: messageID)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = AgentMarkdownRenderCacheFile(
            sessionID: sessionID,
            messageID: messageID,
            contentHash: Self.contentHash(content),
            blocks: blocks,
            createdAt: createdAt
        )
        let data = try encoder().encode(file)
        try data.write(to: url, options: [.atomic])
    }

    public func prewarm(session: AgentSession, minimumContentLength: Int = 800) throws {
        for message in session.messages where message.role == .assistant && message.content.count >= minimumContentLength {
            if try loadBlocks(sessionID: session.id, messageID: message.id, content: message.content) != nil { continue }
            let blocks = AgentMarkdownBlockParser().parse(message.content)
            try saveBlocks(sessionID: session.id, messageID: message.id, content: message.content, blocks: blocks)
        }
    }

    public func cacheURL(sessionID: String, messageID: String) throws -> URL {
        let directories = try storagePaths.ensureSessionArtifactDirectories(sessionID: sessionID, fileManager: fileManager)
        let filename = Self.safeFilename(messageID) + ".json"
        return directories.state
            .appendingPathComponent("markdown-render-cache", isDirectory: true)
            .appendingPathComponent(filename)
    }

    public static func contentHash(_ content: String) -> String {
        AgentMarkdownDocumentCompiler.stableFingerprint(content)
    }

    private static func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let filename = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return filename.isEmpty ? stableFallbackFilename(value) : filename
    }

    private static func stableFallbackFilename(_ value: String) -> String {
        AgentMarkdownDocumentCompiler.stableFingerprint(value)
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
