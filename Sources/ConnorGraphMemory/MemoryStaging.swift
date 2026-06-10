import Foundation
import ConnorGraphCore

public enum ConversationTurnBundleStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case open
    case closed
}

public enum MemoryStagingArtifactKind: String, Codable, Sendable, CaseIterable, Hashable {
    case attachment
    case browserContext = "browser_context"
    case sourceArtifact = "source_artifact"
    case toolCall = "tool_call"
    case toolResult = "tool_result"
}

public struct ConversationTurnMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var role: AgentRole
    public var content: String
    public var createdAt: Date
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        role: AgentRole,
        content: String,
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public struct MemoryStagingArtifact: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var kind: MemoryStagingArtifactKind
    public var content: String
    public var summary: String
    public var createdAt: Date
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        kind: MemoryStagingArtifactKind,
        content: String,
        summary: String = "",
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.summary = summary
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public struct ConversationTurnBundle: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var sessionID: String
    public var userMessages: [ConversationTurnMessage]
    public var assistantMessage: ConversationTurnMessage?
    public var artifacts: [MemoryStagingArtifact]
    public var startedAt: Date
    public var closedAt: Date?
    public var status: ConversationTurnBundleStatus
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        userMessages: [ConversationTurnMessage] = [],
        assistantMessage: ConversationTurnMessage? = nil,
        artifacts: [MemoryStagingArtifact] = [],
        startedAt: Date = Date(),
        closedAt: Date? = nil,
        status: ConversationTurnBundleStatus = .open,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.userMessages = userMessages
        self.assistantMessage = assistantMessage
        self.artifacts = artifacts
        self.startedAt = startedAt
        self.closedAt = closedAt
        self.status = status
        self.metadata = metadata
    }

    public var isClosed: Bool {
        status == .closed
    }

    public var messageCount: Int {
        userMessages.count + (assistantMessage == nil ? 0 : 1)
    }

    public mutating func appendUserMessage(_ content: String, id: String = UUID().uuidString, createdAt: Date = Date()) {
        guard status == .open else { return }
        userMessages.append(
            ConversationTurnMessage(id: id, role: .user, content: content, createdAt: createdAt)
        )
    }

    public mutating func appendArtifact(_ artifact: MemoryStagingArtifact) {
        guard status == .open else { return }
        artifacts.append(artifact)
    }

    public mutating func close(
        assistantContent: String,
        id: String = UUID().uuidString,
        closedAt: Date = Date()
    ) {
        assistantMessage = ConversationTurnMessage(
            id: id,
            role: .assistant,
            content: assistantContent,
            createdAt: closedAt
        )
        self.closedAt = closedAt
        status = .closed
    }

    public static func bundles(from messages: [AgentMessage], sessionID: String) -> [ConversationTurnBundle] {
        var bundles: [ConversationTurnBundle] = []
        var current: ConversationTurnBundle?

        for message in messages {
            switch message.role {
            case .user:
                if current == nil || current?.isClosed == true {
                    current = ConversationTurnBundle(
                        sessionID: sessionID,
                        startedAt: message.createdAt
                    )
                }
                current?.userMessages.append(
                    ConversationTurnMessage(
                        id: message.id,
                        role: .user,
                        content: message.content,
                        createdAt: message.createdAt
                    )
                )
            case .assistant:
                if current == nil {
                    current = ConversationTurnBundle(
                        sessionID: sessionID,
                        startedAt: message.createdAt
                    )
                }
                current?.assistantMessage = ConversationTurnMessage(
                    id: message.id,
                    role: .assistant,
                    content: message.content,
                    createdAt: message.createdAt
                )
                current?.closedAt = message.createdAt
                current?.status = .closed
                if let bundle = current {
                    bundles.append(bundle)
                }
                current = nil
            case .system:
                continue
            }
        }

        if let bundle = current {
            bundles.append(bundle)
        }
        return bundles
    }
}

public enum MemoryStagingBufferStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case active
    case distilling
    case drained
}

public enum MemoryStagingTriggerReason: String, Codable, Sendable, CaseIterable, Hashable {
    case bundleCountReached = "bundle_count_reached"
    case sessionIdle = "session_idle"
    case sessionClosed = "session_closed"
    case explicitRememberRequest = "explicit_remember_request"
    case highValueSignal = "high_value_signal"
    case tokenBudgetExceeded = "token_budget_exceeded"
}

public struct MemoryStagingTriggerPolicy: Codable, Sendable, Equatable {
    public var bundleBatchSize: Int
    public var idleInterval: TimeInterval
    public var tokenBudget: Int

    public init(
        bundleBatchSize: Int = 20,
        idleInterval: TimeInterval = 15 * 60,
        tokenBudget: Int = 12_000
    ) {
        self.bundleBatchSize = bundleBatchSize
        self.idleInterval = idleInterval
        self.tokenBudget = tokenBudget
    }
}

public struct MemoryStagingBuffer: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var sessionID: String
    public var pendingBundles: [ConversationTurnBundle]
    public var tokenEstimate: Int
    public var lastDistilledAt: Date?
    public var status: MemoryStagingBufferStatus
    public var triggerPolicy: MemoryStagingTriggerPolicy
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        pendingBundles: [ConversationTurnBundle] = [],
        tokenEstimate: Int = 0,
        lastDistilledAt: Date? = nil,
        status: MemoryStagingBufferStatus = .active,
        triggerPolicy: MemoryStagingTriggerPolicy = MemoryStagingTriggerPolicy(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.pendingBundles = pendingBundles
        self.tokenEstimate = tokenEstimate
        self.lastDistilledAt = lastDistilledAt
        self.status = status
        self.triggerPolicy = triggerPolicy
        self.metadata = metadata
    }

    public var bundleCount: Int {
        pendingBundles.count
    }

    public var lastActivityAt: Date? {
        pendingBundles.compactMap { $0.closedAt ?? $0.startedAt }.max()
    }

    public mutating func append(_ bundle: ConversationTurnBundle) {
        pendingBundles.append(bundle)
        status = .active
    }

    public func triggerReasons(
        at date: Date = Date(),
        sessionClosed: Bool = false,
        explicitRememberRequest: Bool = false,
        highValueSignal: Bool = false
    ) -> [MemoryStagingTriggerReason] {
        guard !pendingBundles.isEmpty else { return [] }

        var reasons: [MemoryStagingTriggerReason] = []
        if bundleCount >= triggerPolicy.bundleBatchSize {
            reasons.append(.bundleCountReached)
        }
        if let lastActivityAt, date.timeIntervalSince(lastActivityAt) >= triggerPolicy.idleInterval {
            reasons.append(.sessionIdle)
        }
        if sessionClosed {
            reasons.append(.sessionClosed)
        }
        if explicitRememberRequest {
            reasons.append(.explicitRememberRequest)
        }
        if highValueSignal {
            reasons.append(.highValueSignal)
        }
        if tokenEstimate >= triggerPolicy.tokenBudget {
            reasons.append(.tokenBudgetExceeded)
        }
        return reasons
    }

    public mutating func markDistilling() {
        status = .distilling
    }

    public mutating func markDistilled(at date: Date = Date()) {
        pendingBundles.removeAll()
        tokenEstimate = 0
        lastDistilledAt = date
        status = .drained
    }
}
