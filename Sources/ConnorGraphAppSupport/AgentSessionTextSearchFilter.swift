import Foundation
import ConnorGraphCore

public struct AgentSessionTextSearchFilter: Sendable, Equatable {
    public init() {}

    public func filter(_ sessions: [AgentSession], query: String) -> [AgentSession] {
        let terms = normalizedTerms(from: query)
        guard !terms.isEmpty else { return sessions }

        return sessions.filter { session in
            let haystack = searchableText(for: session)
            return terms.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
    }

    private func normalizedTerms(from query: String) -> [String] {
        let normalized = NativeSearchQueryNormalizer.normalize(query)
        let semanticTerms = normalized.displayTokens
            .filter { $0.kind != .phrase }
            .map(\.value)
            .filter { !$0.isEmpty }
        if !semanticTerms.isEmpty { return semanticTerms }
        let displayTerms = normalized.displayTokenValues
            .filter { !$0.isEmpty }
        if !displayTerms.isEmpty { return displayTerms }
        return query
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func searchableText(for session: AgentSession) -> String {
        ([session.title] + session.messages.map(\.content)).joined(separator: "\n")
    }
}
