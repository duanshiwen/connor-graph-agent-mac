import Foundation
import ConnorGraphCore

public enum AttachmentNativePreviewRenderer: String, Sendable, Equatable {
    case none
    case pdfKit
    case quickLook
    case audioPlayer
}

public enum AttachmentPreviewPresentationPolicy: Sendable {
    public static func nativeRenderer(
        for kind: AgentAttachmentKind,
        hasOriginalFileURL: Bool
    ) -> AttachmentNativePreviewRenderer {
        guard hasOriginalFileURL else { return .none }
        switch kind {
        case .pdf:
            return .pdfKit
        case .image, .document, .spreadsheet, .presentation:
            return .quickLook
        case .audio:
            return .audioPlayer
        default:
            return .none
        }
    }
}
