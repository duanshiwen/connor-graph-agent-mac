import Foundation

// MARK: - Session Anchor State

/// Persisted anchor state for context compression.
///
/// After an agent conversation exceeds the token budget, the
/// `ContextCompressionPipeline` summarizes older messages into this
/// compact representation.  New rounds of compression merge into the
/// existing anchor so that the structure grows slowly rather than
/// regenerating from scratch each time.
///
/// Design reference: Factory.ai "Anchored Iterative Summarization"
/// evaluated against 36K production engineering messages – structured
/// summaries with explicit intent / decision / change / next-step
/// fields scored 4.04 accuracy vs Anthropic's 3.74.
public struct SessionAnchorState: Codable, Sendable, Equatable {
    /// What the user is trying to accomplish (refreshed each cycle).
    public var intent: String

    /// Key decisions made during the conversation.
    public var decisions: [String]

    /// Concrete changes that have already been applied.
    public var changes: [String]

    /// Work items that still need to be done.
    public var pendingWork: [String]

    /// Free-form technical details that must survive compression
    /// (file paths, variable names, shell commands, etc.).
    public var preservedDetails: String

    /// IDs of messages that have already been compressed into this
    /// anchor.  Prevents double-counting when compression runs again.
    public var compressedMessageIDs: [String]

    /// Timestamp of the most recent compression cycle.
    public var lastCompressedAt: Date

    /// How many compression cycles have been merged so far.
    public var compressionCycles: Int

    public init(
        intent: String,
        decisions: [String] = [],
        changes: [String] = [],
        pendingWork: [String] = [],
        preservedDetails: String = "",
        compressedMessageIDs: [String] = [],
        lastCompressedAt: Date = Date(),
        compressionCycles: Int = 0
    ) {
        self.intent = intent
        self.decisions = decisions
        self.changes = changes
        self.pendingWork = pendingWork
        self.preservedDetails = preservedDetails
        self.compressedMessageIDs = compressedMessageIDs
        self.lastCompressedAt = lastCompressedAt
        self.compressionCycles = compressionCycles
    }
}
