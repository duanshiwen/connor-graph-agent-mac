import Foundation
import ConnorGraphCore

public enum MailRuntimeError: Error, Sendable, Equatable, CustomStringConvertible {
    case accountNotFound(String)
    case mailboxNotFound(String)
    case messageNotFound(String)
    case draftNotFound(String)
    case approvalRequired(String)
    case unsupportedNetworkOperation(String)

    public var description: String {
        switch self {
        case .accountNotFound(let id): "Mail account not found: \(id)"
        case .mailboxNotFound(let id): "Mail mailbox not found: \(id)"
        case .messageNotFound(let id): "Mail message not found: \(id)"
        case .draftNotFound(let id): "Mail draft not found: \(id)"
        case .approvalRequired(let id): "Approval required: \(id)"
        case .unsupportedNetworkOperation(let op): "Network operation not implemented in commercial skeleton: \(op)"
        }
    }
}
