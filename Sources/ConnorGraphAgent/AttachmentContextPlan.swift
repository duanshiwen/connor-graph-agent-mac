import Foundation
import ConnorGraphCore

public struct AttachmentInlineBlock: Sendable, Equatable {
    public var attachmentID: String
    public var displayName: String
    public var kind: AgentAttachmentKind
    public var content: String
    public var sourceRelativePath: String?
    public var isTruncated: Bool

    public init(
        attachmentID: String,
        displayName: String,
        kind: AgentAttachmentKind,
        content: String,
        sourceRelativePath: String? = nil,
        isTruncated: Bool = false
    ) {
        self.attachmentID = attachmentID
        self.displayName = displayName
        self.kind = kind
        self.content = content
        self.sourceRelativePath = sourceRelativePath
        self.isTruncated = isTruncated
    }
}

public struct AttachmentImageBlock: Sendable, Equatable {
    public var attachmentID: String
    public var displayName: String
    public var kind: AgentAttachmentKind
    public var mimeType: String?
    public var dataURL: String
    public var sourceRelativePath: String

    public init(
        attachmentID: String,
        displayName: String,
        kind: AgentAttachmentKind = .image,
        mimeType: String? = nil,
        dataURL: String,
        sourceRelativePath: String
    ) {
        self.attachmentID = attachmentID
        self.displayName = displayName
        self.kind = kind
        self.mimeType = mimeType
        self.dataURL = dataURL
        self.sourceRelativePath = sourceRelativePath
    }
}

public struct AttachmentProviderNativeBlock: Sendable, Equatable {
    public var attachmentID: String
    public var displayName: String
    public var provider: AgentAttachmentProvider
    public var remoteFileID: String?
    public var remoteURI: String?
    public var reason: String

    public init(
        attachmentID: String,
        displayName: String,
        provider: AgentAttachmentProvider,
        remoteFileID: String? = nil,
        remoteURI: String? = nil,
        reason: String
    ) {
        self.attachmentID = attachmentID
        self.displayName = displayName
        self.provider = provider
        self.remoteFileID = remoteFileID
        self.remoteURI = remoteURI
        self.reason = reason
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
    public var providerNativeBlocks: [AttachmentProviderNativeBlock]
    public var imageBlocks: [AttachmentImageBlock]
    public var estimatedTokens: Int

    public init(
        inlineBlocks: [AttachmentInlineBlock] = [],
        omittedAttachments: [AttachmentOmission] = [],
        providerNativeBlocks: [AttachmentProviderNativeBlock] = [],
        imageBlocks: [AttachmentImageBlock] = [],
        estimatedTokens: Int = 0
    ) {
        self.inlineBlocks = inlineBlocks
        self.omittedAttachments = omittedAttachments
        self.providerNativeBlocks = providerNativeBlocks
        self.imageBlocks = imageBlocks
        self.estimatedTokens = estimatedTokens
    }

    public var isEmpty: Bool {
        inlineBlocks.isEmpty && omittedAttachments.isEmpty && providerNativeBlocks.isEmpty && imageBlocks.isEmpty
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
            if block.isTruncated {
                header += "\nNote: Attachment content truncated before prompt assembly."
            }
            parts.append("""
            \(header)

            ```\(fenceLanguage(for: block.kind))
            \(block.content)
            ```
            """)
        }
        if !plan.imageBlocks.isEmpty {
            let images = plan.imageBlocks
                .map { "- \($0.displayName) (\($0.attachmentID)): image content will be sent to vision-capable model input. Source: \($0.sourceRelativePath)" }
                .joined(separator: "\n")
            parts.append("""
            Vision image attachments:
            \(images)
            """)
        }
        if !plan.providerNativeBlocks.isEmpty {
            let nativeBlocks = plan.providerNativeBlocks
                .map { block in
                    var line = "- \(block.displayName) (\(block.attachmentID)): routed via \(block.provider.rawValue). Reason: \(block.reason)"
                    if let remoteFileID = block.remoteFileID { line += " Remote file ID: \(remoteFileID)." }
                    if let remoteURI = block.remoteURI { line += " Remote URI: \(remoteURI)." }
                    return line
                }
                .joined(separator: "\n")
            parts.append("""
            Provider-native attachment delivery:
            \(nativeBlocks)
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
