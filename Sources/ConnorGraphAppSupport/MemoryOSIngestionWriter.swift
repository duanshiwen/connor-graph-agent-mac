import Foundation
import ConnorGraphCore

public actor MemoryOSIngestionWriter {
    private struct QueuedChatMessage: Sendable {
        var messageID: String
        var sessionID: String
        var role: String
        var content: String
        var occurredAt: Date
        var personReferences: [PersonReference]
    }

    private let facade: AppMemoryOSFacade
    private var queuedMessages: [QueuedChatMessage] = []
    private var isFlushing = false

    public init(facade: AppMemoryOSFacade) {
        self.facade = facade
    }

    public func enqueueChatMessage(
        messageID: String,
        sessionID: String,
        role: String,
        content: String,
        occurredAt: Date,
        personReferences: [PersonReference] = []
    ) {
        queuedMessages.append(QueuedChatMessage(
            messageID: messageID,
            sessionID: sessionID,
            role: role,
            content: content,
            occurredAt: occurredAt,
            personReferences: personReferences
        ))
        Task { try? flush() }
    }

    public func flush() throws {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        while !queuedMessages.isEmpty {
            let message = queuedMessages.removeFirst()
            let formatter = MemoryOSPersonReferenceContextFormatter()
            _ = try facade.ingestChatMessage(
                messageID: message.messageID,
                sessionID: message.sessionID,
                role: message.role,
                content: formatter.content(message.content, personReferences: message.personReferences),
                occurredAt: message.occurredAt,
                metadata: formatter.metadata(personReferences: message.personReferences)
            )
        }
    }
}
