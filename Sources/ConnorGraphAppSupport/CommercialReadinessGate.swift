import Foundation
import ConnorGraphCore
import ConnorGraphAgent

public enum CommercialReadinessPhase: String, Codable, Sendable, Equatable, Hashable, Identifiable, CaseIterable {
    case sessionGovernance
    case claudeSDKSidecar
    case sourcesSkillsAutomations
    case graphMemoryLoop
    case nativeCommercialUI

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sessionGovernance: "Phase 1 · Session Governance"
        case .claudeSDKSidecar: "Phase 2 · Claude SDK Sidecar"
        case .sourcesSkillsAutomations: "Phase 3 · Sources / Skills / Automations"
        case .graphMemoryLoop: "Phase 4 · Graph Memory Loop"
        case .nativeCommercialUI: "Phase 5 · Native Commercial UI"
        }
    }

    public var target: ConnorNativeShellItem {
        switch self {
        case .sessionGovernance: .agentChat
        case .claudeSDKSidecar: .runtimeCenter
        case .sourcesSkillsAutomations: .sources
        case .graphMemoryLoop: .graphMemory
        case .nativeCommercialUI: .settings
        }
    }
}

public enum CommercialReadinessStatus: String, Codable, Sendable, Equatable, Hashable {
    case ready
    case blocked
}

public enum CommercialSessionGovernanceReadiness: Codable, Sendable, Equatable {
    case ready(sessionCount: Int, statusDefinitionCount: Int, labelDefinitionCount: Int, artifactDirectoriesReady: Bool)
    case missing(String)
}

public enum CommercialClaudeSidecarReadiness: Codable, Sendable, Equatable {
    case ready(runtimeStatus: ClaudeSDKSidecarRuntimeStatus, sdkSessionID: String?, healthStatus: String)
    case missing(String)
}

public enum CommercialExtensionRuntimeReadiness: Codable, Sendable, Equatable {
    case ready(enabledSourceCount: Int, loadedSkillCount: Int, enabledAutomationRuleCount: Int)
    case missing(String)
}

public enum CommercialGraphMemoryReadiness: Codable, Sendable, Equatable {
    case ready(pendingCandidateCount: Int, openHoldCount: Int, recentChangeCount: Int)
    case missing(String)
}

public enum CommercialNativeUIReadiness: Codable, Sendable, Equatable {
    case ready(shellItemCount: Int, commandCount: Int, settingsPanelsReady: Bool)
    case missing(String)
}

public struct CommercialReadinessInput: Codable, Sendable, Equatable {
    public var sessionGovernance: CommercialSessionGovernanceReadiness
    public var claudeSidecar: CommercialClaudeSidecarReadiness
    public var extensionRuntime: CommercialExtensionRuntimeReadiness
    public var graphMemory: CommercialGraphMemoryReadiness
    public var nativeUI: CommercialNativeUIReadiness

    public init(
        sessionGovernance: CommercialSessionGovernanceReadiness,
        claudeSidecar: CommercialClaudeSidecarReadiness,
        extensionRuntime: CommercialExtensionRuntimeReadiness,
        graphMemory: CommercialGraphMemoryReadiness,
        nativeUI: CommercialNativeUIReadiness
    ) {
        self.sessionGovernance = sessionGovernance
        self.claudeSidecar = claudeSidecar
        self.extensionRuntime = extensionRuntime
        self.graphMemory = graphMemory
        self.nativeUI = nativeUI
    }
}

public struct CommercialReadinessCard: Codable, Sendable, Equatable, Identifiable {
    public var id: String { phase.rawValue }
    public var phase: CommercialReadinessPhase
    public var title: String
    public var status: CommercialReadinessStatus
    public var evidence: String
    public var metrics: [String: String]
    public var blockingReasons: [String]
    public var target: ConnorNativeShellItem

    public init(
        phase: CommercialReadinessPhase,
        status: CommercialReadinessStatus,
        evidence: String,
        metrics: [String: String] = [:],
        blockingReasons: [String] = []
    ) {
        self.phase = phase
        self.title = phase.title
        self.status = status
        self.evidence = evidence
        self.metrics = metrics
        self.blockingReasons = blockingReasons
        self.target = phase.target
    }
}

public struct CommercialReadinessDashboard: Codable, Sendable, Equatable {
    public var overallStatus: CommercialReadinessStatus
    public var cards: [CommercialReadinessCard]
    public var readyCount: Int
    public var blockedCount: Int
    public var summary: String

    public init(cards: [CommercialReadinessCard]) {
        self.cards = cards
        self.readyCount = cards.filter { $0.status == .ready }.count
        self.blockedCount = cards.filter { $0.status == .blocked }.count
        self.overallStatus = blockedCount == 0 ? .ready : .blocked
        self.summary = blockedCount == 0
            ? "\(readyCount)/\(cards.count) commercial readiness phases ready"
            : "\(readyCount)/\(cards.count) commercial readiness phases ready · \(blockedCount) blocked"
    }
}

public struct CommercialReadinessSnapshotBuilder: Sendable, Equatable {
    public init() {}

    public func build(
        sessions: [AgentSession],
        governanceConfig: AppSessionGovernanceConfig,
        artifactDirectoriesReady: Bool,
        sidecarRecord: ClaudeSDKSidecarRuntimeRecord?,
        sidecarHealthStatus: String?,
        sources: [MCPSourceRuntimeConfiguration],
        skills: [SkillRuntimeDefinition],
        automationConfig: ProductOSAutomationConfig,
        graphMemoryDashboard: GraphMemoryDashboard?,
        shell: ConnorNativeShellPresentation,
        settingsPanelsReady: Bool
    ) -> CommercialReadinessInput {
        let sessionGovernance: CommercialSessionGovernanceReadiness = sessions.isEmpty || !artifactDirectoriesReady
            ? .missing(sessions.isEmpty ? "No persisted session repository configured" : "Session artifact directories are not ready")
            : .ready(
                sessionCount: sessions.count,
                statusDefinitionCount: governanceConfig.statuses.count,
                labelDefinitionCount: governanceConfig.labels.count,
                artifactDirectoriesReady: artifactDirectoriesReady
            )

        let claudeSidecar: CommercialClaudeSidecarReadiness
        if let sidecarRecord {
            claudeSidecar = .ready(
                runtimeStatus: sidecarRecord.status,
                sdkSessionID: sidecarRecord.sdkSessionID,
                healthStatus: sidecarHealthStatus ?? sidecarRecord.status.rawValue
            )
        } else {
            claudeSidecar = .missing("Claude SDK sidecar runtime has not been initialized")
        }

        let enabledSources = sources.filter { $0.status == .enabled }
        let enabledAutomations = automationConfig.rules.filter(\.isEnabled)
        let extensionRuntime: CommercialExtensionRuntimeReadiness = enabledSources.isEmpty
            ? .missing("No enabled source runtime")
            : .ready(
                enabledSourceCount: enabledSources.count,
                loadedSkillCount: skills.count,
                enabledAutomationRuleCount: enabledAutomations.count
            )

        let graphMemory: CommercialGraphMemoryReadiness
        if let graphMemoryDashboard {
            graphMemory = .ready(
                pendingCandidateCount: graphMemoryDashboard.summary.pendingCandidateCount,
                openHoldCount: graphMemoryDashboard.summary.openHoldCount,
                recentChangeCount: graphMemoryDashboard.summary.recentChangeCount
            )
        } else {
            graphMemory = .missing("Graph memory dashboard is not available")
        }

        let nativeUI = CommercialNativeUIReadiness.ready(
            shellItemCount: shell.sidebarGroups.flatMap(\.items).count,
            commandCount: shell.commands.count,
            settingsPanelsReady: settingsPanelsReady
        )

        return CommercialReadinessInput(
            sessionGovernance: sessionGovernance,
            claudeSidecar: claudeSidecar,
            extensionRuntime: extensionRuntime,
            graphMemory: graphMemory,
            nativeUI: nativeUI
        )
    }
}

public struct CommercialReadinessReleaseGateResult: Codable, Sendable, Equatable {
    public var status: CommercialReadinessStatus
    public var dashboard: CommercialReadinessDashboard
    public var blockingCards: [CommercialReadinessCard]
    public var generatedAt: Date
    public var summary: String

    public var isCommercialReady: Bool { status == .ready }

    public init(
        status: CommercialReadinessStatus,
        dashboard: CommercialReadinessDashboard,
        blockingCards: [CommercialReadinessCard],
        generatedAt: Date,
        summary: String
    ) {
        self.status = status
        self.dashboard = dashboard
        self.blockingCards = blockingCards
        self.generatedAt = generatedAt
        self.summary = summary
    }
}

public struct CommercialReadinessReleaseGate: Sendable, Equatable {
    public init() {}

    public func evaluate(_ dashboard: CommercialReadinessDashboard, generatedAt: Date = Date()) -> CommercialReadinessReleaseGateResult {
        let blockingCards = dashboard.cards.filter { $0.status == .blocked }
        let status: CommercialReadinessStatus = blockingCards.isEmpty ? .ready : .blocked
        let prefix = status == .ready ? "READY" : "BLOCKED"
        return CommercialReadinessReleaseGateResult(
            status: status,
            dashboard: dashboard,
            blockingCards: blockingCards,
            generatedAt: generatedAt,
            summary: "\(prefix) · \(dashboard.summary)"
        )
    }
}

public struct CommercialReadinessGate: Sendable, Equatable {
    public init() {}

    public func evaluate(_ input: CommercialReadinessInput) -> CommercialReadinessDashboard {
        CommercialReadinessDashboard(cards: [
            sessionGovernanceCard(input.sessionGovernance),
            claudeSidecarCard(input.claudeSidecar),
            extensionRuntimeCard(input.extensionRuntime),
            graphMemoryCard(input.graphMemory),
            nativeUICard(input.nativeUI)
        ])
    }

    private func sessionGovernanceCard(_ readiness: CommercialSessionGovernanceReadiness) -> CommercialReadinessCard {
        switch readiness {
        case .ready(let sessionCount, let statusDefinitionCount, let labelDefinitionCount, let artifactDirectoriesReady):
            return CommercialReadinessCard(
                phase: .sessionGovernance,
                status: .ready,
                evidence: "\(sessionCount) sessions · \(statusDefinitionCount) statuses · \(labelDefinitionCount) labels · artifacts \(artifactDirectoriesReady ? "ready" : "not ready")",
                metrics: [
                    "sessions": "\(sessionCount)",
                    "statuses": "\(statusDefinitionCount)",
                    "labels": "\(labelDefinitionCount)"
                ]
            )
        case .missing(let reason):
            return blockedCard(phase: .sessionGovernance, reason: reason)
        }
    }

    private func claudeSidecarCard(_ readiness: CommercialClaudeSidecarReadiness) -> CommercialReadinessCard {
        switch readiness {
        case .ready(let runtimeStatus, let sdkSessionID, let healthStatus):
            return CommercialReadinessCard(
                phase: .claudeSDKSidecar,
                status: .ready,
                evidence: "runtime \(runtimeStatus.rawValue) · health \(healthStatus) · sdk session \(sdkSessionID ?? "not yet established")",
                metrics: ["runtime": runtimeStatus.rawValue, "health": healthStatus]
            )
        case .missing(let reason):
            return blockedCard(phase: .claudeSDKSidecar, reason: reason)
        }
    }

    private func extensionRuntimeCard(_ readiness: CommercialExtensionRuntimeReadiness) -> CommercialReadinessCard {
        switch readiness {
        case .ready(let enabledSourceCount, let loadedSkillCount, let enabledAutomationRuleCount):
            return CommercialReadinessCard(
                phase: .sourcesSkillsAutomations,
                status: .ready,
                evidence: "\(enabledSourceCount) sources · \(loadedSkillCount) skills · \(enabledAutomationRuleCount) automations",
                metrics: [
                    "sources": "\(enabledSourceCount)",
                    "skills": "\(loadedSkillCount)",
                    "automations": "\(enabledAutomationRuleCount)"
                ]
            )
        case .missing(let reason):
            return blockedCard(phase: .sourcesSkillsAutomations, reason: reason)
        }
    }

    private func graphMemoryCard(_ readiness: CommercialGraphMemoryReadiness) -> CommercialReadinessCard {
        switch readiness {
        case .ready(let pendingCandidateCount, let openHoldCount, let recentChangeCount):
            return CommercialReadinessCard(
                phase: .graphMemoryLoop,
                status: .ready,
                evidence: "\(pendingCandidateCount) candidates · \(openHoldCount) holds · \(recentChangeCount) recent changes",
                metrics: [
                    "candidates": "\(pendingCandidateCount)",
                    "holds": "\(openHoldCount)",
                    "changes": "\(recentChangeCount)"
                ]
            )
        case .missing(let reason):
            return blockedCard(phase: .graphMemoryLoop, reason: reason)
        }
    }

    private func nativeUICard(_ readiness: CommercialNativeUIReadiness) -> CommercialReadinessCard {
        switch readiness {
        case .ready(let shellItemCount, let commandCount, let settingsPanelsReady):
            return CommercialReadinessCard(
                phase: .nativeCommercialUI,
                status: .ready,
                evidence: "\(shellItemCount) shell items · \(commandCount) commands · settings \(settingsPanelsReady ? "ready" : "partial")",
                metrics: [
                    "shellItems": "\(shellItemCount)",
                    "commands": "\(commandCount)",
                    "settings": settingsPanelsReady ? "ready" : "partial"
                ]
            )
        case .missing(let reason):
            return blockedCard(phase: .nativeCommercialUI, reason: reason)
        }
    }

    private func blockedCard(phase: CommercialReadinessPhase, reason: String) -> CommercialReadinessCard {
        CommercialReadinessCard(
            phase: phase,
            status: .blocked,
            evidence: reason,
            blockingReasons: [reason]
        )
    }
}
