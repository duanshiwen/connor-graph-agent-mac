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
    private let intentNormalizer: AnyMemoryOSUserIntentNormalizer?
    private var queuedMessages: [QueuedChatMessage] = []
    private var isFlushing = false

    public init(facade: AppMemoryOSFacade, intentNormalizer: AnyMemoryOSUserIntentNormalizer? = nil) {
        self.facade = facade
        self.intentNormalizer = intentNormalizer
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
        Task { try? await flush() }
    }

    public func flush() async throws {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        while !queuedMessages.isEmpty {
            let message = queuedMessages.removeFirst()
            let formatter = MemoryOSPersonReferenceContextFormatter()
            var metadata = formatter.metadata(personReferences: message.personReferences)
            var retrievalText: String?
            var normalizationStatus: MemoryOSIntentNormalizationStatus?
            if message.role == "user" {
                do {
                    guard let intentNormalizer else { throw MemoryOSUserIntentNormalizerError.missingStructuredOutput }
                    let normalization = try await intentNormalizer.normalize(message: message.content)
                    retrievalText = normalization.retrievalText
                    normalizationStatus = .succeeded
                    metadata["intent_normalizer_model_id"] = normalization.modelID
                    metadata["intent_normalizer_prompt_version"] = String(normalization.promptVersion)
                } catch {
                    normalizationStatus = .failed
                    metadata["intent_normalization_error"] = String(describing: error)
                }
            }
            _ = try facade.ingestChatMessage(
                messageID: message.messageID,
                sessionID: message.sessionID,
                role: message.role,
                content: message.content,
                occurredAt: message.occurredAt,
                retrievalText: retrievalText,
                normalizationStatus: normalizationStatus,
                metadata: metadata
            )
        }
    }
}
