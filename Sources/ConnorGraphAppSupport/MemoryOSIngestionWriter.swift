import Foundation

public actor MemoryOSIngestionWriter {
    private struct QueuedChatMessage: Sendable {
        var messageID: String
        var sessionID: String
        var role: String
        var content: String
        var occurredAt: Date
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
        occurredAt: Date
    ) {
        queuedMessages.append(QueuedChatMessage(
            messageID: messageID,
            sessionID: sessionID,
            role: role,
            content: content,
            occurredAt: occurredAt
        ))
        Task { try? flush() }
    }

    public func flush() throws {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        while !queuedMessages.isEmpty {
            let message = queuedMessages.removeFirst()
            _ = try facade.ingestChatMessage(
                messageID: message.messageID,
                sessionID: message.sessionID,
                role: message.role,
                content: message.content,
                occurredAt: message.occurredAt
            )
        }
    }
}
