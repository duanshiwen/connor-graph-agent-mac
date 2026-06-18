import Foundation
import ConnorGraphCore

public struct ParsedSkillInvocation: Sendable, Equatable, Identifiable {
    public var id: String
    public var slug: SkillSlug
    public var rawInvocation: String
    public var arguments: String
    public var mode: SkillInvocationMode
    public var range: Range<String.Index>?

    public init(id: String = UUID().uuidString, slug: SkillSlug, rawInvocation: String, arguments: String = "", mode: SkillInvocationMode = .manual, range: Range<String.Index>? = nil) {
        self.id = id
        self.slug = slug
        self.rawInvocation = rawInvocation
        self.arguments = arguments
        self.mode = mode
        self.range = range
    }
}

public struct SkillInvocationParser: Sendable {
    public init() {}

    public func parse(_ text: String, availableSlugs: Set<String> = []) -> [ParsedSkillInvocation] {
        var invocations: [ParsedSkillInvocation] = []
        invocations.append(contentsOf: parseSlashInvocation(text, availableSlugs: availableSlugs))
        invocations.append(contentsOf: parseBracketMentions(text, availableSlugs: availableSlugs))
        var seen = Set<String>()
        return invocations.filter { invocation in
            let key = "\(invocation.slug.rawValue)::\(invocation.rawInvocation)::\(invocation.arguments)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    public func semanticText(_ text: String, skillNames: [String: String]) -> String {
        let pattern = #"\[skill:([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        for match in regex.matches(in: text, range: nsRange).reversed() {
            guard let fullRange = Range(match.range(at: 0), in: text), let bodyRange = Range(match.range(at: 1), in: text) else { continue }
            let body = String(text[bodyRange])
            let slug = body.split(separator: ":").last.map(String.init) ?? body
            let name = skillNames[slug] ?? slug
            result.replaceSubrange(fullRange, with: "[Mentioned skill: \(name) (slug: \(slug))]")
        }
        return result
    }

    public func substituteArguments(in instructions: String, invocation: ParsedSkillInvocation, declaredArguments: [String] = []) -> String {
        let tokens = splitArguments(invocation.arguments)
        var rendered = instructions.replacingOccurrences(of: "$ARGUMENTS", with: invocation.arguments)
        for (index, token) in tokens.enumerated() {
            rendered = rendered.replacingOccurrences(of: "$ARGUMENTS[\(index)]", with: token)
            rendered = rendered.replacingOccurrences(of: "$\(index)", with: token)
        }
        for (index, name) in declaredArguments.enumerated() where index < tokens.count {
            rendered = rendered.replacingOccurrences(of: "$\(name)", with: tokens[index])
        }
        if !invocation.arguments.isEmpty && !instructions.contains("$ARGUMENTS") && !instructions.contains("$0") && declaredArguments.allSatisfy({ !instructions.contains("$\($0)") }) {
            rendered += "\n\nARGUMENTS: \(invocation.arguments)"
        }
        return rendered
    }

    public func splitArguments(_ arguments: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var iterator = arguments.makeIterator()
        while let character = iterator.next() {
            if character == "\"" || character == "'" {
                if quote == character { quote = nil } else if quote == nil { quote = character } else { current.append(character) }
            } else if character == " " && quote == nil {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private func parseSlashInvocation(_ text: String, availableSlugs: Set<String>) -> [ParsedSkillInvocation] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return [] }
        let withoutSlash = String(trimmed.dropFirst())
        let parts = withoutSlash.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let command = parts.first else { return [] }
        let slug = normalizeSlug(String(command))
        guard SkillSlug(slug).isValid else { return [] }
        guard availableSlugs.isEmpty || availableSlugs.contains(slug) else { return [] }
        let arguments = parts.count > 1 ? String(parts[1]) : ""
        return [ParsedSkillInvocation(slug: SkillSlug(slug), rawInvocation: "/\(command)", arguments: arguments, mode: .manual)]
    }

    private func parseBracketMentions(_ text: String, availableSlugs: Set<String>) -> [ParsedSkillInvocation] {
        let pattern = #"\[skill:([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let bodyRange = Range(match.range(at: 1), in: text), let fullRange = Range(match.range(at: 0), in: text) else { return nil }
            let body = String(text[bodyRange])
            let slug = normalizeSlug(body.split(separator: ":").last.map(String.init) ?? body)
            guard SkillSlug(slug).isValid else { return nil }
            guard availableSlugs.isEmpty || availableSlugs.contains(slug) else { return nil }
            return ParsedSkillInvocation(slug: SkillSlug(slug), rawInvocation: String(text[fullRange]), arguments: "", mode: .manual, range: fullRange)
        }
    }

    private func normalizeSlug(_ value: String) -> String {
        if value.contains(":") { return value.split(separator: ":").last.map(String.init) ?? value }
        return value
    }
}
