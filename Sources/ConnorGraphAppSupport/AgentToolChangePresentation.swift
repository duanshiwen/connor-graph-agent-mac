import Foundation

public struct AgentToolChangePresentation: Codable, Sendable, Equatable, Identifiable {
    public enum Format: String, Codable, Sendable, Equatable {
        case unifiedDiff
        case beforeAfter
    }

    public var id: String
    public var path: String?
    public var format: Format
    public var diffText: String?
    public var beforeText: String?
    public var afterText: String?
    public var isTruncated: Bool
    public var omittedCharacterCount: Int

    public init?(
        invocation: AgentToolInvocationPresentation,
        displayPolicy: AgentToolOutputDisplayPolicy = AgentToolOutputDisplayPolicy()
    ) {
        guard invocation.semanticKind == .editFile || invocation.semanticKind == .writeFile else { return nil }

        let arguments = Self.dictionary(from: invocation.argumentsJSON)
        let result = Self.dictionary(from: invocation.resultJSON)
        let path = Self.path(from: arguments) ?? Self.path(from: result) ?? invocation.target ?? Self.path(fromUnifiedDiff: invocation.outputText)

        if let diff = Self.diff(from: result) ?? Self.diff(from: arguments) ?? Self.diff(fromText: invocation.outputText) {
            let display = displayPolicy.display(for: diff)
            self.id = "tool-change-\(invocation.callID)"
            self.path = path ?? Self.path(fromUnifiedDiff: diff)
            self.format = .unifiedDiff
            self.diffText = display.previewText
            self.beforeText = nil
            self.afterText = nil
            self.isTruncated = display.isTruncated || invocation.isOutputTruncated
            self.omittedCharacterCount = display.omittedCharacterCount
            return
        }

        let before = Self.beforeText(from: arguments) ?? Self.beforeText(from: result)
        let after = Self.afterText(from: arguments) ?? Self.afterText(from: result)
        guard before != nil || after != nil else { return nil }

        let generatedDiff = Self.makeSimpleUnifiedDiff(path: path, before: before ?? "", after: after ?? "")
        let display = displayPolicy.display(for: generatedDiff)
        self.id = "tool-change-\(invocation.callID)"
        self.path = path
        self.format = .beforeAfter
        self.diffText = display.previewText
        self.beforeText = before
        self.afterText = after
        self.isTruncated = display.isTruncated || invocation.isOutputTruncated
        self.omittedCharacterCount = display.omittedCharacterCount
    }

    private static func dictionary(from json: String?) -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func path(from object: [String: Any]?) -> String? {
        guard let object else { return nil }
        let keys = ["path", "filePath", "file_path", "target", "filename", "name"]
        for key in keys {
            if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func diff(from object: [String: Any]?) -> String? {
        guard let object else { return nil }
        let keys = ["diff", "patch", "unifiedDiff", "unified_diff", "changes"]
        for key in keys {
            if let value = object[key] as? String, looksLikeUnifiedDiff(value) {
                return value
            }
        }
        return nil
    }

    private static func diff(fromText text: String?) -> String? {
        guard let text, looksLikeUnifiedDiff(text) else { return nil }
        return text
    }

    private static func beforeText(from object: [String: Any]?) -> String? {
        guard let object else { return nil }
        let keys = ["oldText", "old_text", "before", "beforeText", "original", "previousText"]
        for key in keys {
            if let value = object[key] as? String { return value }
        }
        return nil
    }

    private static func afterText(from object: [String: Any]?) -> String? {
        guard let object else { return nil }
        let keys = ["newText", "new_text", "after", "afterText", "replacement", "updatedText"]
        for key in keys {
            if let value = object[key] as? String { return value }
        }
        return nil
    }

    private static func looksLikeUnifiedDiff(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.contains("--- ") && trimmed.contains("+++ ")
            || trimmed.contains("@@") && (trimmed.contains("\n+") || trimmed.contains("\n-"))
    }

    private static func path(fromUnifiedDiff text: String?) -> String? {
        guard let text else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let plusLine = lines.first(where: { $0.hasPrefix("+++ ") }) {
            return normalizeDiffPath(String(plusLine.dropFirst(4)))
        }
        if let minusLine = lines.first(where: { $0.hasPrefix("--- ") }) {
            return normalizeDiffPath(String(minusLine.dropFirst(4)))
        }
        return nil
    }

    private static func normalizeDiffPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "/dev/null" else { return nil }
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }

    private static func makeSimpleUnifiedDiff(path: String?, before: String, after: String) -> String {
        let displayPath = path ?? "file"
        var lines: [String] = [
            "--- a/\(displayPath)",
            "+++ b/\(displayPath)",
            "@@ -1 +1 @@"
        ]
        lines.append(contentsOf: before.split(separator: "\n", omittingEmptySubsequences: false).map { "-\($0)" })
        lines.append(contentsOf: after.split(separator: "\n", omittingEmptySubsequences: false).map { "+\($0)" })
        return lines.joined(separator: "\n")
    }
}
