import Foundation
import ConnorGraphCore

public actor ChatSessionTitleGenerationWorker {
    public init() {}

    public func userPrompts(repository: AppChatSessionRepository, sessionID: String) throws -> [String] {
        guard let session = try repository.loadSession(id: sessionID) else { return [] }
        return session.messages
            .filter { $0.role == .user }
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func renameSession(repository: AppChatSessionRepository, sessionID: String, title: String) throws -> AgentSession {
        try repository.renameSession(sessionID: sessionID, title: title)
    }
}
