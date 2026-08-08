import Foundation
import ConnorGraphCore

/// 会话历史检索源（对齐 Android RoomSessionSearchSource）：FTS 索引为主，
/// 命中不足时回退到全量会话/消息扫描并去重合并，保证不遗漏 UI 全局搜索能命中的内容。
public struct HybridSessionSearchProvider: SessionSearchProviding {
    private let index: any SessionSearchProviding
    private let loadSessions: @Sendable () throws -> [AgentSession]

    public init(index: any SessionSearchProviding, loadSessions: @escaping @Sendable () throws -> [AgentSession]) {
        self.index = index
        self.loadSessions = loadSessions
    }

    public func search(query: String, limit: Int) async throws -> [SessionSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }
        let indexed = try await index.search(query: query, limit: limit)
        guard indexed.count < limit else { return indexed }
        let sessions = try loadSessions()
        var merged = indexed
        var seen = Set(indexed.map(\.id))
        for session in sessions {
            guard !seen.contains(session.id) else { continue }
            let haystack = Self.searchableText(for: session)
            guard haystack.contains(normalizedQuery) else { continue }
            seen.insert(session.id)
            merged.append(SessionSearchResult(
                id: session.id,
                title: session.title.isEmpty ? "新对话" : session.title,
                snippet: Self.snippet(from: haystack, query: normalizedQuery),
                updatedAt: session.updatedAt,
                messageCount: session.messages.count
            ))
        }
        return Array(merged.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    private static func searchableText(for session: AgentSession) -> String {
        session.messages.map { "\($0.role.rawValue): \($0.content)" }
            .joined(separator: "\n")
    }

    private static func snippet(from text: String, query: String) -> String {
        guard let range = text.range(of: query) else { return String(text.prefix(120)) }
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let begin = max(0, start - 36)
        let end = min(text.count, begin + 120)
        let lower = text.index(text.startIndex, offsetBy: begin)
        let upper = text.index(text.startIndex, offsetBy: end)
        return (begin > 0 ? "…" : "") + String(text[lower..<upper]) + (end < text.count ? "…" : "")
    }
}
