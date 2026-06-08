import Foundation
import ConnorGraphCore

public enum LegacyImportError: Error, Equatable {
    case missingFrontmatter
    case invalidDocument
}

public enum FrontmatterValue: Equatable, Sendable {
    case string(String)
    case array([FrontmatterValue])

    public var stringValue: String {
        switch self {
        case .string(let value): value
        case .array(let values): values.map(\.stringValue).joined(separator: ", ")
        }
    }

    public var arrayValue: [FrontmatterValue] {
        switch self {
        case .string(let value): [.string(value)]
        case .array(let values): values
        }
    }
}

public struct LegacyMarkdownDocument: Equatable, Sendable {
    public var sourcePath: String
    public var frontmatter: [String: FrontmatterValue]
    public var body: String

    public init(sourcePath: String = "", frontmatter: [String: FrontmatterValue], body: String) {
        self.sourcePath = sourcePath
        self.frontmatter = frontmatter
        self.body = body
    }
}

public struct LegacyImportResult: Equatable, Sendable {
    public var nodes: [GraphNode]
    public var edges: [SemanticEdge]

    public init(nodes: [GraphNode] = [], edges: [SemanticEdge] = []) {
        self.nodes = nodes
        self.edges = edges
    }
}

public struct FrontmatterParser: Sendable {
    public init() {}

    public func parse(_ markdown: String, sourcePath: String = "") throws -> LegacyMarkdownDocument {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else { throw LegacyImportError.missingFrontmatter }
        let remainder = String(normalized.dropFirst(4))
        guard let close = remainder.range(of: "\n---") else { throw LegacyImportError.missingFrontmatter }
        let yaml = String(remainder[..<close.lowerBound])
        let bodyStart = remainder[close.upperBound...]
        let body = bodyStart.hasPrefix("\n") ? String(bodyStart.dropFirst()) : String(bodyStart)
        return LegacyMarkdownDocument(sourcePath: sourcePath, frontmatter: parseYamlSubset(yaml), body: body)
    }

    private func parseYamlSubset(_ yaml: String) -> [String: FrontmatterValue] {
        var result: [String: FrontmatterValue] = [:]
        var currentArrayKey: String?
        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("- "), let key = currentArrayKey {
                var existing = result[key]?.arrayValue ?? []
                existing.append(.string(clean(String(trimmed.dropFirst(2)))))
                result[key] = .array(existing)
                continue
            }
            currentArrayKey = nil
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if rawValue.isEmpty {
                result[key] = .array([])
                currentArrayKey = key
            } else if rawValue.hasPrefix("[") && rawValue.hasSuffix("]") {
                let inner = rawValue.dropFirst().dropLast()
                let values = inner.split(separator: ",").map { FrontmatterValue.string(clean(String($0))) }
                result[key] = .array(values)
            } else {
                result[key] = .string(clean(rawValue))
            }
        }
        return result
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
    }
}

public struct LegacyMarkdownImporter: Sendable {
    public init() {}

    public func importDocument(_ document: LegacyMarkdownDocument) throws -> LegacyImportResult {
        let node = primaryNode(for: document)
        var edges: [SemanticEdge] = []

        if let workObjectID = document.frontmatter["work_object_id"]?.stringValue,
           node.id != workObjectNodeID(workObjectID) {
            edges.append(SemanticEdge(
                id: "edge-\(node.id)-belongs-to-\(workObjectNodeID(workObjectID))",
                sourceNodeID: node.id,
                targetNodeID: workObjectNodeID(workObjectID),
                relation: .belongsTo,
                fact: "\(node.title) belongs to \(workObjectID)"
            ))
        }

        if let questionID = document.frontmatter["question_id"]?.stringValue, node.type == .answer {
            edges.append(SemanticEdge(
                id: "edge-\(questionID)-answered-by-\(node.id)",
                sourceNodeID: questionID,
                targetNodeID: node.id,
                relation: .answeredBy,
                fact: "\(questionID) is answered by \(node.title)"
            ))
        }

        for related in document.frontmatter["related"]?.arrayValue ?? [] {
            let targetID = documentNodeID(related.stringValue)
            edges.append(SemanticEdge(
                id: "edge-\(node.id)-related-to-\(targetID)",
                sourceNodeID: node.id,
                targetNodeID: targetID,
                relation: .relatedTo,
                fact: "\(node.title) is related to \(related.stringValue)"
            ))
        }

        for answerRef in document.frontmatter["answer_cache_refs"]?.arrayValue ?? [] {
            let targetID = answerNodeID(answerRef.stringValue)
            edges.append(SemanticEdge(
                id: "edge-\(node.id)-answered-by-\(targetID)",
                sourceNodeID: node.id,
                targetNodeID: targetID,
                relation: .answeredBy,
                fact: "\(node.title) is answered by \(answerRef.stringValue)"
            ))
        }

        return LegacyImportResult(nodes: [node], edges: edges)
    }

    private func primaryNode(for document: LegacyMarkdownDocument) -> GraphNode {
        let type = nodeType(for: document)
        let title = document.frontmatter["title"]?.stringValue ?? fallbackTitle(from: document.sourcePath)
        let summary = document.frontmatter["summary"]?.stringValue ?? ""
        let id: String
        switch type {
        case .workObject:
            id = workObjectNodeID(document.frontmatter["work_object_id"]?.stringValue ?? slug(title))
        case .answer:
            id = answerNodeID(document.sourcePath.isEmpty ? title : document.sourcePath)
        case .question:
            id = "question-\(slug(title))"
        case .decision:
            id = "decision-\(slug(title))"
        case .procedure:
            id = "procedure-\(slug(title))"
        case .person:
            id = "person-\(slug(title))"
        default:
            id = documentNodeID(document.sourcePath.isEmpty ? title : document.sourcePath)
        }
        return GraphNode(id: id, type: type, title: title, summary: summary, sourcePath: document.sourcePath)
    }

    private func nodeType(for document: LegacyMarkdownDocument) -> NodeType {
        let path = document.sourcePath.lowercased()
        let knowledgeType = document.frontmatter["knowledge_type"]?.stringValue.lowercased()
        if path.contains("work-objects") || document.frontmatter["work_object_id"] != nil && path.contains("projects") { return .workObject }
        if knowledgeType == "question" || path.contains("questions") { return .question }
        if knowledgeType == "answer" || path.contains("answer-cache") { return .answer }
        if path.contains("decisions") { return .decision }
        if path.contains("sops") || path.contains("runbooks") { return .procedure }
        if path.contains("persons/profiles") || path.contains("people") { return .person }
        return .document
    }

    private func workObjectNodeID(_ value: String) -> String { "work-object-\(slug(value))" }
    private func answerNodeID(_ value: String) -> String { "answer-\(slug(value))" }
    private func documentNodeID(_ value: String) -> String { "document-\(slug(value))" }

    private func fallbackTitle(from path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ")
    }

    private func slug(_ value: String) -> String {
        let lower = value.lowercased()
        var scalars = ""
        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.unicodeScalars.append(scalar)
            } else {
                scalars.append("-")
            }
        }
        while scalars.contains("--") { scalars = scalars.replacingOccurrences(of: "--", with: "-") }
        return scalars.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
