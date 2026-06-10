import Foundation
import ConnorGraphCore

public struct MemoryIngestionResult: Sendable, Equatable {
    public var buffer: MemoryStagingBuffer
    public var appendedBundleIDs: [String]
    public var updatedBundleIDs: [String]
    public var triggerReasons: [MemoryStagingTriggerReason]

    public init(
        buffer: MemoryStagingBuffer,
        appendedBundleIDs: [String] = [],
        updatedBundleIDs: [String] = [],
        triggerReasons: [MemoryStagingTriggerReason] = []
    ) {
        self.buffer = buffer
        self.appendedBundleIDs = appendedBundleIDs
        self.updatedBundleIDs = updatedBundleIDs
        self.triggerReasons = triggerReasons
    }
}

public struct MemoryIngestionOptions: Sendable, Equatable {
    public var sessionClosed: Bool
    public var explicitRememberRequest: Bool
    public var highValueSignal: Bool
    public var now: Date

    public init(
        sessionClosed: Bool = false,
        explicitRememberRequest: Bool = false,
        highValueSignal: Bool = false,
        now: Date = Date()
    ) {
        self.sessionClosed = sessionClosed
        self.explicitRememberRequest = explicitRememberRequest
        self.highValueSignal = highValueSignal
        self.now = now
    }
}

public struct MemoryIngestionService: Sendable {
    public init() {}

    public func ingest(
        session: AgentSession,
        into buffer: MemoryStagingBuffer? = nil,
        artifacts: [MemoryStagingArtifact] = [],
        options: MemoryIngestionOptions = MemoryIngestionOptions()
    ) -> MemoryIngestionResult {
        var workingBuffer = buffer ?? MemoryStagingBuffer(sessionID: session.id)
        var appendedBundleIDs: [String] = []
        var updatedBundleIDs: [String] = []

        let existingMessageIDs = Set(
            workingBuffer.pendingBundles.flatMap { bundle in
                bundle.userMessages.map(\.id) + [bundle.assistantMessage?.id].compactMap { $0 }
            }
        )
        let newMessages = session.messages.filter { !existingMessageIDs.contains($0.id) }
        let newBundles = ConversationTurnBundle.bundles(from: newMessages, sessionID: session.id)

        for bundle in newBundles {
            if mergeIfPossible(bundle, into: &workingBuffer) {
                updatedBundleIDs.append(workingBuffer.pendingBundles.last?.id ?? bundle.id)
            } else {
                workingBuffer.append(bundle)
                appendedBundleIDs.append(bundle.id)
            }
        }

        if !artifacts.isEmpty, attach(artifacts, to: &workingBuffer, sessionID: session.id) {
            if let lastID = workingBuffer.pendingBundles.last?.id {
                updatedBundleIDs.append(lastID)
            }
        }

        workingBuffer.tokenEstimate = estimateTokens(for: workingBuffer)
        let reasons = workingBuffer.triggerReasons(
            at: options.now,
            sessionClosed: options.sessionClosed,
            explicitRememberRequest: options.explicitRememberRequest,
            highValueSignal: options.highValueSignal
        )

        return MemoryIngestionResult(
            buffer: workingBuffer,
            appendedBundleIDs: appendedBundleIDs,
            updatedBundleIDs: Array(Set(updatedBundleIDs)),
            triggerReasons: reasons
        )
    }

    public func ingestUserMessage(
        _ message: AgentMessage,
        sessionID: String,
        into buffer: MemoryStagingBuffer? = nil,
        artifacts: [MemoryStagingArtifact] = [],
        options: MemoryIngestionOptions = MemoryIngestionOptions()
    ) -> MemoryIngestionResult {
        let session = AgentSession(
            id: sessionID,
            messages: [message],
            createdAt: message.createdAt,
            updatedAt: message.createdAt
        )
        return ingest(session: session, into: buffer, artifacts: artifacts, options: options)
    }

    public func ingestAssistantMessage(
        _ message: AgentMessage,
        sessionID: String,
        into buffer: MemoryStagingBuffer,
        options: MemoryIngestionOptions = MemoryIngestionOptions()
    ) -> MemoryIngestionResult {
        let session = AgentSession(
            id: sessionID,
            messages: [message],
            createdAt: message.createdAt,
            updatedAt: message.createdAt
        )
        return ingest(session: session, into: buffer, options: options)
    }

    private func mergeIfPossible(_ bundle: ConversationTurnBundle, into buffer: inout MemoryStagingBuffer) -> Bool {
        guard let lastIndex = buffer.pendingBundles.indices.last else { return false }
        guard buffer.pendingBundles[lastIndex].status == .open else { return false }

        if !bundle.userMessages.isEmpty, bundle.assistantMessage == nil {
            buffer.pendingBundles[lastIndex].userMessages.append(contentsOf: bundle.userMessages)
            return true
        }

        if bundle.userMessages.isEmpty, let assistantMessage = bundle.assistantMessage {
            buffer.pendingBundles[lastIndex].assistantMessage = assistantMessage
            buffer.pendingBundles[lastIndex].closedAt = assistantMessage.createdAt
            buffer.pendingBundles[lastIndex].status = .closed
            return true
        }

        if !bundle.userMessages.isEmpty, let assistantMessage = bundle.assistantMessage {
            buffer.pendingBundles[lastIndex].userMessages.append(contentsOf: bundle.userMessages)
            buffer.pendingBundles[lastIndex].assistantMessage = assistantMessage
            buffer.pendingBundles[lastIndex].closedAt = assistantMessage.createdAt
            buffer.pendingBundles[lastIndex].status = .closed
            return true
        }

        return false
    }

    private func attach(_ artifacts: [MemoryStagingArtifact], to buffer: inout MemoryStagingBuffer, sessionID: String) -> Bool {
        if let lastIndex = buffer.pendingBundles.indices.last, buffer.pendingBundles[lastIndex].status == .open {
            buffer.pendingBundles[lastIndex].artifacts.append(contentsOf: artifacts)
            return true
        }

        let startedAt = artifacts.map(\.createdAt).min() ?? Date()
        let bundle = ConversationTurnBundle(
            sessionID: sessionID,
            artifacts: artifacts,
            startedAt: startedAt
        )
        buffer.append(bundle)
        return true
    }

    private func estimateTokens(for buffer: MemoryStagingBuffer) -> Int {
        let characterCount = buffer.pendingBundles.reduce(0) { partial, bundle in
            let userCharacters = bundle.userMessages.reduce(0) { $0 + $1.content.count }
            let assistantCharacters = bundle.assistantMessage?.content.count ?? 0
            let artifactCharacters = bundle.artifacts.reduce(0) { $0 + $1.content.count + $1.summary.count }
            return partial + userCharacters + assistantCharacters + artifactCharacters
        }
        return max(1, characterCount / 4)
    }
}
