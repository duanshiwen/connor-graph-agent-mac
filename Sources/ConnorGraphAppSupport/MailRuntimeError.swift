import Foundation
import ConnorGraphCore

public enum MailRuntimeError: Error, Sendable, Equatable, CustomStringConvertible {
    case accountNotFound(String)
    case mailboxNotFound(String)
    case messageNotFound(String)
    case draftNotFound(String)
    case approvalRequired(String)
    case identityNotFound(String)
    case identityCannotSend(String)
    case missingOutgoingEndpoint(String)
    case missingCredential(String)
    case missingRecipients(String)
    case missingApprovedEnvelopeHash(String)
    case envelopeHashMismatch(expected: String, actual: String)
    case invalidDraftState(String)
    case attachmentSessionRequired
    case attachmentNotFound(String)
    case attachmentNotReady(String)
    case invalidAttachment(String)
    case attachmentChanged(String)
    case attachmentTooLarge(id: String, maximumBytes: Int64)
    case attachmentsTooLarge(maximumBytes: Int64)
    case unsupportedNetworkOperation(String)

    public var description: String {
        switch self {
        case .accountNotFound(let id): "Mail account not found: \(id)"
        case .mailboxNotFound(let id): "Mail mailbox not found: \(id)"
        case .messageNotFound(let id): "Mail message not found: \(id)"
        case .draftNotFound(let id): "Mail draft not found: \(id)"
        case .approvalRequired(let id): "Approval required: \(id)"
        case .identityNotFound(let id): "Mail identity not found: \(id)"
        case .identityCannotSend(let id): "Mail identity cannot send: \(id)"
        case .missingOutgoingEndpoint(let id): "Mail account has no outgoing SMTP endpoint: \(id)"
        case .missingCredential(let id): "Missing mail credential: \(id)"
        case .missingRecipients(let id): "Mail draft has no recipients: \(id)"
        case .missingApprovedEnvelopeHash(let id): "Mail draft has no approved envelope hash: \(id)"
        case .envelopeHashMismatch(let expected, let actual): "Mail draft envelope hash mismatch: expected \(expected), actual \(actual)"
        case .invalidDraftState(let state): "Mail draft cannot be sent in state: \(state)"
        case .attachmentSessionRequired: "Mail attachments require the current chat session"
        case .attachmentNotFound(let id): "Mail attachment not found in the current session: \(id)"
        case .attachmentNotReady(let id): "Mail attachment is not ready: \(id)"
        case .invalidAttachment(let id): "Mail attachment is not a valid regular file: \(id)"
        case .attachmentChanged(let id): "Mail attachment changed after it was imported: \(id)"
        case .attachmentTooLarge(let id, let maximumBytes): "Mail attachment exceeds the \(maximumBytes)-byte limit: \(id)"
        case .attachmentsTooLarge(let maximumBytes): "Mail attachments exceed the \(maximumBytes)-byte total limit"
        case .unsupportedNetworkOperation(let op): "Network operation not implemented in commercial skeleton: \(op)"
        }
    }
}
