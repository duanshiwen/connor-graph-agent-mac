import Foundation
import ConnorGraphCore
import ConnorGraphSearch

// MARK: - Compressed Context

/// Result of a context compression cycle.
public struct CompressedContext: Sendable {
    /// The updated anchor state (persist across compressions).
    public let anchor: SessionAnchorState
    /// Messages that survive compression (the recent tail).
    public let recentMessages: [AgentMessage]
    /// Human-readable summary of what happened (for logging / UI).
    public let compressionSummary: String
    /// How many messages were evicted.
    public let evictedMessageCount: Int
}

// MARK: - Context Compression Pipeline

/// Anchored Iterative Summarization pipeline.
///
/// When the cumulative token count of a session exceeds the configured
/// threshold, this pipeline:
///
/// 1. Splits messages into an **evictable span** (older) and a
///    **recent tail** (kept verbatim).
/// 2. Summarizes the evictable span via the LLM, producing structured
///    fields: intent, decisions, changes, pending work, preserved
///    technical details.
/// 3. Merges the new summary into the existing `SessionAnchorState`
///    (iterative — never regenerates from scratch).
/// 4. Returns the updated anchor + the recent messages.
///
/// On compression failure, falls back to Sliding Window: keeps only
/// the recent tail and discards the anchor.
public struct ContextCompressionPipeline<Provider: LLMProvider>: @unchecked Sendable {
    private let provider: Provider
    private let recentMessageKeepCount: Int
    private let tokenCounter: SessionTokenCounter

    public init(
        provider: Provider,
        recentMessageKeepCount: Int = 7,
        tokenCounter: SessionTokenCounter = .init()
    ) {
        self.provider = provider
        self.recentMessageKeepCount = recentMessageKeepCount
        self.tokenCounter = tokenCounter
    }

    // MARK: - Public API

    /// Compress the session, returning the new anchor + recent messages.
    public func compress(
        messages: [AgentMessage],
        existingAnchor: SessionAnchorState?
    ) async throws -> CompressedContext {
        let (evictable, recent) = splitMessages(messages)

        guard !evictable.isEmpty else {
            // Nothing to compress — everything fits in the recent tail.
            return CompressedContext(
                anchor: existingAnchor ?? .empty,
                recentMessages: recent,
                compressionSummary: "No messages to compress (all fit in recent tail)",
                evictedMessageCount: 0
            )
        }

        do {
            return try await compressWithLLM(
                evictable: evictable,
                recent: recent,
                existingAnchor: existingAnchor
            )
        } catch {
            // Fallback: Sliding Window (keep only recent, no anchor)
            return slidingWindowFallback(
                recent: recent,
                error: error
            )
        }
    }

    // MARK: - Split

    /// Split messages into evictable (older) and recent (kept).
    ///
    /// Messages are ordered chronologically (oldest first).
    /// The most recent `recentMessageKeepCount` messages are always kept.
    func splitMessages(_ messages: [AgentMessage]) -> (evictable: [AgentMessage], recent: [AgentMessage]) {
        guard messages.count > recentMessageKeepCount else {
            return ([], messages)
        }
        let splitIndex = messages.count - recentMessageKeepCount
        return (
            evictable: Array(messages[0..<splitIndex]),   // older (to be summarized)
            recent: Array(messages[splitIndex...])          // recent tail (kept verbatim)
        )
    }

    // MARK: - LLM Compression

    private func compressWithLLM(
        evictable: [AgentMessage],
        recent: [AgentMessage],
        existingAnchor: SessionAnchorState?
    ) async throws -> CompressedContext {
        let prompt = Self.compressionPrompt(
            evictable: evictable,
            existingAnchor: existingAnchor
        )
        let context = AgentContext(query: "Compress context", items: [])
        let response = try await provider.complete(prompt: prompt, context: context)

        let parsed = Self.parseCompressedAnchor(
            responseText: response.text,
            existingAnchor: existingAnchor,
            evictedMessageIDs: evictable.map(\.id),
            evictedMessageCount: evictable.count
        )

        return CompressedContext(
            anchor: parsed,
            recentMessages: recent,
            compressionSummary: "Compressed \(evictable.count) messages (cycle \(parsed.compressionCycles))",
            evictedMessageCount: evictable.count
        )
    }

    // MARK: - Fallback

    private func slidingWindowFallback(
        recent: [AgentMessage],
        error: Error
    ) -> CompressedContext {
        let fallbackAnchor = SessionAnchorState(
            intent: "Context compression failed (\(error.localizedDescription)). Keeping only recent messages.",
            decisions: [],
            changes: [],
            pendingWork: [],
            preservedDetails: "",
            compressedMessageIDs: [],
            lastCompressedAt: Date(),
            compressionCycles: 1
        )
        return CompressedContext(
            anchor: fallbackAnchor,
            recentMessages: recent,
            compressionSummary: "⚠️ Compression failed, sliding window fallback applied (\(recent.count) messages kept)",
            evictedMessageCount: 0
        )
    }

    // MARK: - Prompt Construction

    private static func compressionPrompt(
        evictable: [AgentMessage],
        existingAnchor: SessionAnchorState?
    ) -> String {
        var lines: [String] = []

        lines.append("""
        You are compressing an agent conversation history to preserve critical context.

        Analyze the conversation below and produce a structured anchor state.
        """)

        if let anchor = existingAnchor, anchor.compressionCycles > 0 {
            lines.append("""

            ## Existing compressed state (from prior rounds):
            - Intent: \(anchor.intent)
            - Decisions: \(anchor.decisions.joined(separator: "; "))
            - Changes: \(anchor.changes.joined(separator: "; "))
            - Pending: \(anchor.pendingWork.joined(separator: "; "))
            - Details: \(anchor.preservedDetails)

            MERGE the new information into the existing state.  Do not discard existing decisions/changes that are still relevant.  Update intent only if it has shifted.
            """)
        }

        let transcript = evictable.map { msg in
            "\(msg.role.rawValue.capitalized): \(msg.content)"
        }.joined(separator: "\n\n")

        lines.append("""

        ## Conversation to compress:
        \(transcript)

        ## Output format (strict):
        INTENT: <1-2 sentence description of the user's goal>
        DECISIONS: <semicolon-separated list, or NONE>
        CHANGES: <semicolon-separated list of concrete changes made, or NONE>
        PENDING: <semicolon-separated list of next steps, or NONE>
        DETAILS: <file paths, variable names, commands, API endpoints — anything that must be preserved verbatim>
        """)

        return lines.joined(separator: "\n")
    }

    // MARK: - Response Parsing

    /// Parse the LLM's structured response into a `SessionAnchorState`.
    static func parseCompressedAnchor(
        responseText: String,
        existingAnchor: SessionAnchorState?,
        evictedMessageIDs: [String],
        evictedMessageCount: Int
    ) -> SessionAnchorState {
        let lines = responseText.components(separatedBy: "\n")

        var intent = ""
        var decisions: [String] = []
        var changes: [String] = []
        var pendingWork: [String] = []
        var details = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("INTENT:") {
                intent = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("DECISIONS:") {
                let value = String(trimmed.dropFirst(10)).trimmingCharacters(in: .whitespaces)
                decisions = Self.parseList(value)
            } else if trimmed.hasPrefix("CHANGES:") {
                let value = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                changes = Self.parseList(value)
            } else if trimmed.hasPrefix("PENDING:") {
                let value = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                pendingWork = Self.parseList(value)
            } else if trimmed.hasPrefix("DETAILS:") {
                details = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            }
        }

        // Merge with existing anchor if present
        let existing = existingAnchor
        let mergedDecisions = (existing?.decisions ?? []) + decisions
        let mergedChanges = (existing?.changes ?? []) + changes
        let mergedPending = pendingWork.isEmpty ? (existing?.pendingWork ?? []) : pendingWork
        let mergedDetails = [existing?.preservedDetails, details]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let mergedIDs = (existing?.compressedMessageIDs ?? []) + evictedMessageIDs

        return SessionAnchorState(
            intent: intent.isEmpty ? (existing?.intent ?? "Unknown") : intent,
            decisions: mergedDecisions,
            changes: mergedChanges,
            pendingWork: mergedPending,
            preservedDetails: mergedDetails,
            compressedMessageIDs: mergedIDs,
            lastCompressedAt: Date(),
            compressionCycles: (existing?.compressionCycles ?? 0) + 1
        )
    }

    private static func parseList(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty && trimmed.uppercased() != "NONE" else { return [] }
        return trimmed
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Convenience

extension SessionAnchorState {
    /// Empty anchor for initialization.
    public static let empty = SessionAnchorState(
        intent: "",
        decisions: [],
        changes: [],
        pendingWork: [],
        preservedDetails: "",
        compressedMessageIDs: [],
        lastCompressedAt: Date(),
        compressionCycles: 0
    )
}
