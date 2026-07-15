import Foundation

public struct AgentToolOutputDisplay: Codable, Sendable, Equatable {
    public var previewText: String
    public var isTruncated: Bool
    public var originalCharacterCount: Int
    public var omittedCharacterCount: Int

    public init(previewText: String, isTruncated: Bool, originalCharacterCount: Int, omittedCharacterCount: Int) {
        self.previewText = previewText
        self.isTruncated = isTruncated
        self.originalCharacterCount = originalCharacterCount
        self.omittedCharacterCount = omittedCharacterCount
    }
}

public struct AgentToolOutputDisplayPolicy: Sendable {
    public var previewCharacterLimit: Int

    public init(previewCharacterLimit: Int = 16_000) {
        self.previewCharacterLimit = max(0, previewCharacterLimit)
    }

    public func display(for output: String?) -> AgentToolOutputDisplay {
        guard let output, !output.isEmpty else {
            return AgentToolOutputDisplay(
                previewText: "",
                isTruncated: false,
                originalCharacterCount: 0,
                omittedCharacterCount: 0
            )
        }

        let originalCount = output.count
        guard originalCount > previewCharacterLimit else {
            return AgentToolOutputDisplay(
                previewText: output,
                isTruncated: false,
                originalCharacterCount: originalCount,
                omittedCharacterCount: 0
            )
        }

        let preview = String(output.prefix(previewCharacterLimit))
        return AgentToolOutputDisplay(
            previewText: preview,
            isTruncated: true,
            originalCharacterCount: originalCount,
            omittedCharacterCount: max(0, originalCount - preview.count)
        )
    }
}
