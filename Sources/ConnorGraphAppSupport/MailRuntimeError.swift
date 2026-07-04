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
        case .unsupportedNetworkOperation(let op): "Network operation not implemented in commercial skeleton: \(op)"
        }
    }
}
