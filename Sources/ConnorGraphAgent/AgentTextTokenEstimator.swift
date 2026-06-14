import Foundation

public struct AgentTextTokenEstimator: Sendable, Equatable {
    public var cjkCharactersPerToken: Double
    public var nonCJKCharactersPerToken: Double

    public init(
        cjkCharactersPerToken: Double = 1.8,
        nonCJKCharactersPerToken: Double = 3.8
    ) {
        self.cjkCharactersPerToken = max(0.1, cjkCharactersPerToken)
        self.nonCJKCharactersPerToken = max(0.1, nonCJKCharactersPerToken)
    }

    public func estimateTokenCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var cjkCount = 0
        var nonCJKCount = 0
        for scalar in text.unicodeScalars {
            if Self.isCJK(scalar) {
                cjkCount += 1
            } else {
                nonCJKCount += 1
            }
        }
        let estimated = Double(cjkCount) / cjkCharactersPerToken + Double(nonCJKCount) / nonCJKCharactersPerToken
        return max(1, Int(ceil(estimated)))
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,   // CJK Extension A
             0x4E00...0x9FFF,   // CJK Unified Ideographs
             0xF900...0xFAFF,   // CJK Compatibility Ideographs
             0x20000...0x2A6DF, // CJK Extension B
             0x2A700...0x2B73F, // CJK Extension C
             0x2B740...0x2B81F, // CJK Extension D
             0x2B820...0x2CEAF, // CJK Extension E/F
             0x3000...0x303F,   // CJK punctuation
             0x3040...0x309F,   // Hiragana
             0x30A0...0x30FF,   // Katakana
             0xAC00...0xD7AF:   // Hangul syllables
            return true
        default:
            return false
        }
    }
}
