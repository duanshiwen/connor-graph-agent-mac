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
        case .claudeSDKSidecar: .settings
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
    case ready(
        sessionCount: Int,
        statusDefinitionCount: Int,
        labelDefinitionCount: Int,
        artifactDirectoriesReady: Bool,
        persistedRunCount: Int = 0,
        journalEventCount: Int = 0,
        pendingPlanCount: Int = 0,
        branchRecordCount: Int = 0,
        restorableSnapshotReady: Bool = true
    )
    case missing(String)
}

public enum CommercialClaudeSidecarReadiness: Codable, Sendable, Equatable {
    case ready(
        runtimeStatus: ClaudeSDKSidecarRuntimeStatus,
        sdkSessionID: String?,
        healthStatus: String,
        protocolVersion: Int = 2,
        sdkCWD: String? = nil,
        hasHeartbeat: Bool = false,
        lastDiagnosticMessage: String? = nil,
        failureCode: ClaudeSDKSidecarFailureCode? = nil,
        recoverability: ClaudeSDKSidecarRecoverability? = nil,
        ownsProductState: Bool = false,
        governedPermissionMode: Bool = true
    )
    case missing(String)
}

public enum CommercialExtensionRuntimeReadiness: Codable, Sendable, Equatable {
    case ready(
        enabledSourceCount: Int,
        loadedSkillCount: Int,
        enabledAutomationRuleCount: Int,
        healthySourceCount: Int = 0,
        discoveredToolCount: Int = 0,
        auditedInvocationCount: Int = 0,
        governedSourcePolicy: Bool = true
    )
    case missing(String)
}

public enum CommercialGraphMemoryReadiness: Codable, Sendable, Equatable {
    case ready(
        pendingCandidateCount: Int,
        openHoldCount: Int,
        recentChangeCount: Int,
        contextReady: Bool = false,
        ingestionReady: Bool = false,
        distillationReady: Bool = false,
        reviewReady: Bool = true,
        contextItemCount: Int = 0,
        stagedBundleCount: Int = 0,
        distillationCandidateCount: Int = 0,
        feedbackSignalCount: Int = 0
    )
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
        sourceHealthRecords: [MCPSourceRuntimeHealthRecord] = [],
        sourceAuditRecords: [MCPSourceRuntimeAuditRecord] = [],
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
                artifactDirectoriesReady: artifactDirectoriesReady,
                persistedRunCount: 0,
                journalEventCount: 0,
                pendingPlanCount: 0,
                branchRecordCount: 0,
                restorableSnapshotReady: artifactDirectoriesReady
            )

        let claudeSidecar: CommercialClaudeSidecarReadiness
        if let sidecarRecord {
            claudeSidecar = .ready(
                runtimeStatus: sidecarRecord.status,
                sdkSessionID: sidecarRecord.sdkSessionID,
                healthStatus: sidecarHealthStatus ?? sidecarRecord.status.rawValue,
                protocolVersion: sidecarRecord.protocolVersion,
                sdkCWD: sidecarRecord.sdkCWD,
                hasHeartbeat: sidecarRecord.lastHeartbeatAt != nil,
                lastDiagnosticMessage: sidecarRecord.lastDiagnosticMessage,
                failureCode: sidecarRecord.failureCode,
                recoverability: sidecarRecord.recoverability,
                ownsProductState: false,
                governedPermissionMode: true
            )
        } else {
            claudeSidecar = .missing("Claude SDK sidecar runtime has not been initialized")
        }

        let enabledSources = sources.filter { $0.status == .enabled }
        let enabledAutomations = automationConfig.rules.filter(\.isEnabled)
        let enabledSourceIDs = Set(enabledSources.map(\.sourceID))
        let healthySourceCount = sourceHealthRecords.filter { enabledSourceIDs.contains($0.sourceID) && $0.healthStatus == .healthy }.count
        let discoveredToolCount = sourceHealthRecords
            .filter { enabledSourceIDs.contains($0.sourceID) }
            .reduce(0) { $0 + $1.discoveredToolCount }
        let governedSourcePolicy = enabledSources.allSatisfy { $0.graphWritePolicy != .allowAll }
        let extensionRuntime: CommercialExtensionRuntimeReadiness
        if enabledSources.isEmpty {
            extensionRuntime = .missing("No enabled source runtime")
        } else if !sourceHealthRecords.isEmpty && healthySourceCount == 0 {
            extensionRuntime = .missing("Enabled source runtime exists but no healthy source has been discovered")
        } else if !governedSourcePolicy {
            extensionRuntime = .missing("Enabled source runtime includes unsafe graph write policy")
        } else {
            extensionRuntime = .ready(
                enabledSourceCount: enabledSources.count,
                loadedSkillCount: skills.count,
                enabledAutomationRuleCount: enabledAutomations.count,
                healthySourceCount: healthySourceCount,
                discoveredToolCount: discoveredToolCount,
                auditedInvocationCount: sourceAuditRecords.count,
                governedSourcePolicy: governedSourcePolicy
            )
        }

        let graphMemory: CommercialGraphMemoryReadiness
        if let graphMemoryDashboard {
            graphMemory = .ready(
                pendingCandidateCount: graphMemoryDashboard.summary.pendingCandidateCount,
                openHoldCount: graphMemoryDashboard.summary.openHoldCount,
                recentChangeCount: graphMemoryDashboard.summary.recentChangeCount,
                contextReady: graphMemoryDashboard.summary.contextReady,
                ingestionReady: graphMemoryDashboard.summary.ingestionReady,
                distillationReady: graphMemoryDashboard.summary.distillationReady,
                reviewReady: graphMemoryDashboard.summary.reviewReady,
                contextItemCount: graphMemoryDashboard.summary.contextItemCount,
                stagedBundleCount: graphMemoryDashboard.summary.stagedBundleCount,
                distillationCandidateCount: graphMemoryDashboard.summary.distillationCandidateCount,
                feedbackSignalCount: graphMemoryDashboard.summary.feedbackSignalCount
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
        case .ready(
            let sessionCount,
            let statusDefinitionCount,
            let labelDefinitionCount,
            let artifactDirectoriesReady,
            let persistedRunCount,
            let journalEventCount,
            let pendingPlanCount,
            let branchRecordCount,
            let restorableSnapshotReady
        ):
            let blockedReasons = [
                artifactDirectoriesReady ? nil : "Session artifact directories are not ready",
                restorableSnapshotReady ? nil : "Session OS restore snapshot is not ready"
            ].compactMap { $0 }
            return CommercialReadinessCard(
                phase: .sessionGovernance,
                status: blockedReasons.isEmpty ? .ready : .blocked,
                evidence: "\(sessionCount) sessions · \(statusDefinitionCount) statuses · \(labelDefinitionCount) labels · \(persistedRunCount) runs · \(journalEventCount) journal events · \(pendingPlanCount) pending plans · \(branchRecordCount) branches · artifacts \(artifactDirectoriesReady ? "ready" : "not ready") · restore \(restorableSnapshotReady ? "ready" : "not ready")",
                metrics: [
                    "sessions": "\(sessionCount)",
                    "statuses": "\(statusDefinitionCount)",
                    "labels": "\(labelDefinitionCount)",
                    "runs": "\(persistedRunCount)",
                    "journalEvents": "\(journalEventCount)",
                    "pendingPlans": "\(pendingPlanCount)",
                    "branches": "\(branchRecordCount)",
                    "restore": restorableSnapshotReady ? "ready" : "blocked"
                ],
                blockingReasons: blockedReasons
            )
        case .missing(let reason):
            return blockedCard(phase: .sessionGovernance, reason: reason)
        }
    }

    private func claudeSidecarCard(_ readiness: CommercialClaudeSidecarReadiness) -> CommercialReadinessCard {
        switch readiness {
        case .ready(
            let runtimeStatus,
            let sdkSessionID,
            let healthStatus,
            let protocolVersion,
            let sdkCWD,
            let hasHeartbeat,
            let lastDiagnosticMessage,
            let failureCode,
            let recoverability,
            let ownsProductState,
            let governedPermissionMode
        ):
            let blockedReasons = [
                ownsProductState ? "Claude SDK sidecar must not own Connor product state" : nil,
                governedPermissionMode ? nil : "Claude SDK sidecar is not governed by Connor permission mode",
                protocolVersion >= 2 ? nil : "Claude SDK sidecar protocol v2 is required for production diagnostics"
            ].compactMap { $0 }
            return CommercialReadinessCard(
                phase: .claudeSDKSidecar,
                status: blockedReasons.isEmpty ? .ready : .blocked,
                evidence: "runtime \(runtimeStatus.rawValue) · health \(healthStatus) · protocol v\(protocolVersion) · sdk session \(sdkSessionID ?? "not yet established") · cwd \(sdkCWD ?? "unknown") · heartbeat \(hasHeartbeat ? "seen" : "not seen") · sovereignty \(ownsProductState ? "violated" : "Connor-owned")",
                metrics: [
                    "runtime": runtimeStatus.rawValue,
                    "health": healthStatus,
                    "protocol": "v\(protocolVersion)",
                    "sdkSession": sdkSessionID ?? "not-established",
                    "sdkCWD": sdkCWD ?? "unknown",
                    "heartbeat": hasHeartbeat ? "seen" : "missing",
                    "diagnostic": lastDiagnosticMessage ?? "none",
                    "failureCode": failureCode?.rawValue ?? "none",
                    "recoverability": recoverability?.rawValue ?? "unknown",
                    "productState": ownsProductState ? "sdk-owned" : "Connor-owned",
                    "permission": governedPermissionMode ? "Connor-governed" : "unsafe"
                ],
                blockingReasons: blockedReasons
            )
        case .missing(let reason):
            return blockedCard(phase: .claudeSDKSidecar, reason: reason)
        }
    }

    private func extensionRuntimeCard(_ readiness: CommercialExtensionRuntimeReadiness) -> CommercialReadinessCard {
        switch readiness {
        case .ready(
            let enabledSourceCount,
            let loadedSkillCount,
            let enabledAutomationRuleCount,
            let healthySourceCount,
            let discoveredToolCount,
            let auditedInvocationCount,
            let governedSourcePolicy
        ):
            let blockingReasons = governedSourcePolicy ? [] : ["Source graph write policy is not Connor-governed"]
            var metrics = [
                "sources": "\(enabledSourceCount)",
                "skills": "\(loadedSkillCount)",
                "automations": "\(enabledAutomationRuleCount)"
            ]
            if healthySourceCount > 0 || discoveredToolCount > 0 || auditedInvocationCount > 0 || !governedSourcePolicy {
                metrics["healthySources"] = "\(healthySourceCount)"
                metrics["discoveredTools"] = "\(discoveredToolCount)"
                metrics["sourceAudits"] = "\(auditedInvocationCount)"
                metrics["governedSourcePolicy"] = governedSourcePolicy ? "true" : "false"
            }
            return CommercialReadinessCard(
                phase: .sourcesSkillsAutomations,
                status: blockingReasons.isEmpty ? .ready : .blocked,
                evidence: "\(enabledSourceCount) sources · \(healthySourceCount) healthy · \(discoveredToolCount) tools · \(loadedSkillCount) skills · \(enabledAutomationRuleCount) automations",
                metrics: metrics,
                blockingReasons: blockingReasons
            )
        case .missing(let reason):
            return blockedCard(phase: .sourcesSkillsAutomations, reason: reason)
        }
    }

    private func graphMemoryCard(_ readiness: CommercialGraphMemoryReadiness) -> CommercialReadinessCard {
        switch readiness {
        case .ready(
            let pendingCandidateCount,
            let openHoldCount,
            let recentChangeCount,
            let contextReady,
            let ingestionReady,
            let distillationReady,
            let reviewReady,
            let contextItemCount,
            let stagedBundleCount,
            let distillationCandidateCount,
            let feedbackSignalCount
        ):
            let hasCoreEvidence = contextReady || ingestionReady || distillationReady || reviewReady
            let blockingReasons = hasCoreEvidence ? [] : ["Graph memory is not wired into the Agent core runtime"]
            var metrics = [
                "candidates": "\(pendingCandidateCount)",
                "holds": "\(openHoldCount)",
                "changes": "\(recentChangeCount)"
            ]
            if contextReady || ingestionReady || distillationReady || contextItemCount > 0 || stagedBundleCount > 0 || distillationCandidateCount > 0 || feedbackSignalCount > 0 {
                metrics["contextReady"] = contextReady ? "true" : "false"
                metrics["ingestionReady"] = ingestionReady ? "true" : "false"
                metrics["distillationReady"] = distillationReady ? "true" : "false"
                metrics["reviewReady"] = reviewReady ? "true" : "false"
                metrics["contextItems"] = "\(contextItemCount)"
                metrics["stagedBundles"] = "\(stagedBundleCount)"
                metrics["distillationCandidates"] = "\(distillationCandidateCount)"
                metrics["feedbackSignals"] = "\(feedbackSignalCount)"
            }
            return CommercialReadinessCard(
                phase: .graphMemoryLoop,
                status: blockingReasons.isEmpty ? .ready : .blocked,
                evidence: "\(pendingCandidateCount) candidates · \(openHoldCount) holds · \(recentChangeCount) recent changes · context \(contextReady ? "ready" : "not ready") · ingestion \(ingestionReady ? "ready" : "not ready") · distillation \(distillationReady ? "ready" : "not ready")",
                metrics: metrics,
                blockingReasons: blockingReasons
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
