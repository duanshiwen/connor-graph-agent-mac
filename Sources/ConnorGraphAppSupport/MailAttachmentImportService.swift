import Foundation
import ConnorGraphCore

public struct MailAttachmentImportService: Sendable, Equatable {
    public init() {}
    public func importDescriptor(_ descriptor: MailAttachmentDescriptor, sessionID: String) -> String {
        "session://\(sessionID)/mail-attachments/\(descriptor.id.rawValue)/\(descriptor.filename)"
    }
}
