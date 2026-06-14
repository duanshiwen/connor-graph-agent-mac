import Foundation
import ConnorGraphCore

public struct AttachmentInlineBlock: Sendable, Equatable {
    public var attachmentID: String
    public var displayName: String
    public var kind: AgentAttachmentKind
    public var content: String
    public var sourceRelativePath: String?

    public init(
        attachmentID: String,
        displayName: String,
        kind: AgentAttachmentKind,
        content: String,
        sourceRelativePath: String? = nil
    ) {
        self.attachmentID = attachmentID
        self.displayName = displayName
        self.kind = kind
        self.content = content
        self.sourceRelativePath = sourceRelativePath
    }
}

public struct AttachmentOmission: Sendable, Equatable {
    public var attachmentID: String
    public var displayName: String
    public var reason: String

    public init(attachmentID: String, displayName: String, reason: String) {
        self.attachmentID = attachmentID
        self.displayName = displayName
        self.reason = reason
    }
}

public struct AttachmentContextPlan: Sendable, Equatable {
    public var inlineBlocks: [AttachmentInlineBlock]
    public var omittedAttachments: [AttachmentOmission]
    public var estimatedTokens: Int

    public init(
        inlineBlocks: [AttachmentInlineBlock] = [],
        omittedAttachments: [AttachmentOmission] = [],
        estimatedTokens: Int = 0
    ) {
        self.inlineBlocks = inlineBlocks
        self.omittedAttachments = omittedAttachments
        self.estimatedTokens = estimatedTokens
    }

    public var isEmpty: Bool {
        inlineBlocks.isEmpty && omittedAttachments.isEmpty
    }
}

public struct AgentAttachmentContextSection: Sendable, Equatable {
    public var plan: AttachmentContextPlan

    public init(plan: AttachmentContextPlan) {
        self.plan = plan
    }

    public var renderedText: String {
        guard !plan.isEmpty else { return "" }
        var parts: [String] = ["## User Attachments"]
        for block in plan.inlineBlocks {
            var header = "Attachment: \(block.displayName)\nID: \(block.attachmentID)\nKind: \(block.kind.rawValue)"
            if let source = block.sourceRelativePath {
                header += "\nSource: \(source)"
            }
            parts.append("""
            \(header)

            ```\(fenceLanguage(for: block.kind))
            \(block.content)
            ```
            """)
        }
        if !plan.omittedAttachments.isEmpty {
            let omitted = plan.omittedAttachments
                .map { "- \($0.displayName) (\($0.attachmentID)): \($0.reason)" }
                .joined(separator: "\n")
            parts.append("""
            Omitted attachments:
            \(omitted)
            """)
        }
        return parts.joined(separator: "\n\n")
    }

    private func fenceLanguage(for kind: AgentAttachmentKind) -> String {
        switch kind {
        case .markdown: return "markdown"
        case .json: return "json"
        case .csv: return "csv"
        case .html: return "html"
        case .code: return ""
        default: return ""
        }
    }
}
