import Foundation

// MARK: - Session Token Budget Status

public enum SessionTokenBudgetStatus: Int, Comparable, Sendable, CaseIterable {
    /// Cumulative tokens well below warning threshold.
    case normal = 0
    /// Approaching compression zone (50% of context window).
    case warning = 1
    /// Compression should be triggered (70% of context window).
    case shouldCompress = 2
    /// Emergency — force compression immediately (85% of context window).
    case safetyNet = 3

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Session Context Budget

/// Percentage-based context window budget.
///
/// Rather than using a fixed token count (which would be wrong for
/// models with different context windows), `SessionContextBudget`
/// expresses thresholds as **fractions of the model's context window**.
///
/// Industry reference points (for a 200K window):
///
/// | System                 | Threshold | Tokens |
/// |------------------------|-----------|--------|
/// | Hermes Agent           | 50%       | 100K   |
/// | Hermes Gateway         | 85%       | 170K   |
/// | Claude Code (CLI)      | 95%       | 190K   |
/// | Claude Code (VSCode)   | ~65%      | ~130K  |
/// | MorphLLM recommendation| 80%       | 160K   |
/// | **This implementation**| **70%**   | 140K   |
///
/// The 70% default balances the Hermes conservative approach with
/// the MorphLLM aggressive approach.  Warning fires at 50% to give
/// the user early notice.
public struct SessionContextBudget: Sendable, Equatable {
    /// The model's total context window in tokens.
    public let contextWindowSize: Int

    /// Fraction of the context window that triggers a warning.
    public static let warningRatio: Double = 0.50

    /// Fraction of the context window that triggers compression.
    public static let compressionRatio: Double = 0.70

    /// Fraction of the context window that forces emergency compression.
    public static let safetyNetRatio: Double = 0.85

    public init(contextWindowSize: Int) {
        self.contextWindowSize = contextWindowSize
    }

    /// Token count at which the UI should start showing a warning.
    public var warningThreshold: Int {
        Int(Double(contextWindowSize) * Self.warningRatio)
    }

    /// Token count at which compression should be triggered.
    public var compressionThreshold: Int {
        Int(Double(contextWindowSize) * Self.compressionRatio)
    }

    /// Token count at which emergency compression is forced.
    public var safetyNetThreshold: Int {
        Int(Double(contextWindowSize) * Self.safetyNetRatio)
    }

    /// Determine the current budget status for a given token count.
    public func status(tokenCount: Int) -> SessionTokenBudgetStatus {
        if tokenCount >= safetyNetThreshold { return .safetyNet }
        if tokenCount >= compressionThreshold { return .shouldCompress }
        if tokenCount >= warningThreshold { return .warning }
        return .normal
    }

    /// Percentage of context window used (0.0 – 1.0+).
    public func usagePercent(tokenCount: Int) -> Double {
        Double(tokenCount) / Double(contextWindowSize)
    }
}

// MARK: - Well-known context window sizes

extension SessionContextBudget {
    /// Common context window sizes for popular models (2026 Q2).
    public static let wellKnownContextWindows: [String: Int] = [
        // Anthropic Claude
        "claude-4": 200_000,
        "claude-opus-4": 200_000,
        "claude-sonnet-4": 200_000,
        "claude-3.5-sonnet": 200_000,
        "claude-3-opus": 200_000,
        // OpenAI GPT
        "gpt-4o": 128_000,
        "gpt-4-turbo": 128_000,
        "o3": 200_000,
        "o4-mini": 200_000,
        // Google Gemini
        "gemini-2.5-pro": 1_048_576,
        "gemini-2.5-flash": 1_048_576,
        "gemini-2.0-pro": 2_097_152,
        // DeepSeek
        "deepseek-chat": 128_000,
        "deepseek-reasoner": 128_000,
    ]

    /// Try to infer the context window size from a model identifier.
    /// Falls back to 200_000 if the model is unknown.
    public static func inferContextWindowSize(modelID: String?) -> Int {
        guard let modelID = modelID?.lowercased() else { return 200_000 }
        for (key, size) in wellKnownContextWindows {
            if modelID.contains(key) { return size }
        }
        return 200_000  // safe default for most modern models
    }
}
