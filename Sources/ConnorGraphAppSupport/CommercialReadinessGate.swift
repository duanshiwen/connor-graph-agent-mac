import Foundation
import ConnorGraphCore
import ConnorGraphAgent

public enum CommercialReadinessPhase: String, Codable, Sendable, Equatable, Hashable, Identifiable, CaseIterable {
    case sessionGovernance
    case claudeSDKSidecar
    case sourcesSkillsAutomations
    case graphMemoryLoop
    case nativeCommercialUI
    case localAPICLIAutomationSurface

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sessionGovernance: "Phase 1 · Session Governance"
        case .claudeSDKSidecar: "Phase 2 · Claude SDK Sidecar"
        case .sourcesSkillsAutomations: "Phase 3 · Sources / Skills / Automations"
        case .graphMemoryLoop: "Phase 4 · Graph Memory Loop"
        case .nativeCommercialUI: "Phase 5 · Native Commercial UI"
        case .localAPICLIAutomationSurface: "Phase 6 · Local API / CLI / Automation Surface"
        }
    }

    public var target: ConnorNativeShellItem {
        switch self {
        case .sessionGovernance: .agentChat
        case .claudeSDKSidecar: .settings
        case .sourcesSkillsAutomations: .sources
        case .graphMemoryLoop: .graphMemory
        case .nativeCommercialUI: .settings
        case .localAPICLIAutomationSurface: .localAutomationSurface
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
    case ready(
        shellItemCount: Int,
        commandCount: Int,
        settingsPanelsReady: Bool,
        homeSurfaceReady: Bool = false,
        readinessDashboardLinked: Bool = false,
        primaryActionCount: Int = 0,
        emptyStateCount: Int = 0,
        keyboardShortcutCount: Int = 0,
        settingsSectionCount: Int = 0
    )
    case missing(String)
}

public enum CommercialLocalAutomationSurfaceReadiness: Codable, Sendable, Equatable {
    case ready(
        endpointCount: Int,
        cliCommandCount: Int,
        automationTriggerCount: Int,
        dryRunEvaluationReady: Bool,
        reviewedExecutionGateReady: Bool,
        auditSurfaceReady: Bool,
        localOnly: Bool
    )
    case missing(String)
}

public struct CommercialReadinessInput: Codable, Sendable, Equatable {
    public var sessionGovernance: CommercialSessionGovernanceReadiness
    public var claudeSidecar: CommercialClaudeSidecarReadiness
    public var extensionRuntime: CommercialExtensionRuntimeReadiness
    public var graphMemory: CommercialGraphMemoryReadiness
    public var nativeUI: CommercialNativeUIReadiness
    public var localAutomationSurface: CommercialLocalAutomationSurfaceReadiness

    public init(
        sessionGovernance: CommercialSessionGovernanceReadiness,
        claudeSidecar: CommercialClaudeSidecarReadiness,
        extensionRuntime: CommercialExtensionRuntimeReadiness,
        graphMemory: CommercialGraphMemoryReadiness,
        nativeUI: CommercialNativeUIReadiness,
        localAutomationSurface: CommercialLocalAutomationSurfaceReadiness = .ready(
            endpointCount: ConnorLocalAutomationSurfacePresentation.default.endpoints.count,
            cliCommandCount: ConnorLocalAutomationSurfacePresentation.default.cliCommands.count,
            automationTriggerCount: ConnorLocalAutomationSurfacePresentation.default.supportedTriggers.count,
            dryRunEvaluationReady: true,
            reviewedExecutionGateReady: true,
            auditSurfaceReady: true,
            localOnly: true
        )
    ) {
        self.sessionGovernance = sessionGovernance
        self.claudeSidecar = claudeSidecar
        self.extensionRuntime = extensionRuntime
        self.graphMemory = graphMemory
        self.nativeUI = nativeUI
        self.localAutomationSurface = localAutomationSurface
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

public struct CommercialReadinessGate: Sendable, Equatable {
    public init() {}

    public func evaluate(_ input: CommercialReadinessInput) -> CommercialReadinessDashboard {
        CommercialReadinessDashboard(cards: [
            sessionGovernanceCard(input.sessionGovernance),
            claudeSidecarCard(input.claudeSidecar),
            extensionRuntimeCard(input.extensionRuntime),
            graphMemoryCard(input.graphMemory),
            nativeUICard(input.nativeUI),
            localAutomationSurfaceCard(input.localAutomationSurface)
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
        case .ready(
            let shellItemCount,
            let commandCount,
            let settingsPanelsReady,
            let homeSurfaceReady,
            let readinessDashboardLinked,
            let primaryActionCount,
            let emptyStateCount,
            let keyboardShortcutCount,
            let settingsSectionCount
        ):
            let hasTrain5Evidence = homeSurfaceReady || readinessDashboardLinked || primaryActionCount > 0 || emptyStateCount > 0 || keyboardShortcutCount > 0 || settingsSectionCount > 0
            let blockingReasons = hasTrain5Evidence ? [
                shellItemCount > 0 ? nil : "Native shell has no navigation items",
                commandCount > 0 ? nil : "Native shell has no commands",
                settingsPanelsReady ? nil : "Settings panels are not ready",
                homeSurfaceReady ? nil : "Default home surface is not available",
                readinessDashboardLinked ? nil : "Commercial readiness dashboard is not linked",
                primaryActionCount >= 4 ? nil : "Not enough primary native actions",
                emptyStateCount >= 3 ? nil : "Not enough empty states for commercial UI",
                keyboardShortcutCount >= 6 ? nil : "Not enough keyboard shortcuts",
                settingsSectionCount >= 6 ? nil : "Settings surface is incomplete"
            ].compactMap { $0 } : []
            return CommercialReadinessCard(
                phase: .nativeCommercialUI,
                status: blockingReasons.isEmpty ? .ready : .blocked,
                evidence: "\(shellItemCount) shell items · \(commandCount) commands · \(primaryActionCount) primary actions · \(keyboardShortcutCount) shortcuts · \(settingsSectionCount) settings sections",
                metrics: [
                    "shellItems": "\(shellItemCount)",
                    "commands": "\(commandCount)",
                    "settings": settingsPanelsReady ? "ready" : "partial",
                    "homeSurfaceReady": homeSurfaceReady ? "true" : "false",
                    "readinessDashboardLinked": readinessDashboardLinked ? "true" : "false",
                    "primaryActions": "\(primaryActionCount)",
                    "emptyStates": "\(emptyStateCount)",
                    "keyboardShortcuts": "\(keyboardShortcutCount)",
                    "settingsSections": "\(settingsSectionCount)"
                ],
                blockingReasons: blockingReasons
            )
        case .missing(let reason):
            return blockedCard(phase: .nativeCommercialUI, reason: reason)
        }
    }

    private func localAutomationSurfaceCard(_ readiness: CommercialLocalAutomationSurfaceReadiness) -> CommercialReadinessCard {
        switch readiness {
        case .ready(let endpointCount, let cliCommandCount, let automationTriggerCount, let dryRunEvaluationReady, let reviewedExecutionGateReady, let auditSurfaceReady, let localOnly):
            let blockingReasons = [
                endpointCount >= 6 ? nil : "Local API endpoint catalog is incomplete",
                cliCommandCount >= 6 ? nil : "CLI command catalog is incomplete",
                automationTriggerCount >= 4 ? nil : "Automation trigger coverage is incomplete",
                dryRunEvaluationReady ? nil : "Automation dry-run evaluation is not ready",
                reviewedExecutionGateReady ? nil : "Reviewed execution gate is not ready",
                auditSurfaceReady ? nil : "Local automation audit surface is not ready",
                localOnly ? nil : "Local API surface must remain local-only in this phase"
            ].compactMap { $0 }
            return CommercialReadinessCard(
                phase: .localAPICLIAutomationSurface,
                status: blockingReasons.isEmpty ? .ready : .blocked,
                evidence: "\(endpointCount) endpoints · \(cliCommandCount) CLI commands · \(automationTriggerCount) triggers · dry-run \(dryRunEvaluationReady ? "ready" : "blocked") · reviewed gate \(reviewedExecutionGateReady ? "ready" : "blocked") · local-only \(localOnly ? "true" : "false")",
                metrics: [
                    "endpoints": "\(endpointCount)",
                    "cliCommands": "\(cliCommandCount)",
                    "triggers": "\(automationTriggerCount)",
                    "dryRun": dryRunEvaluationReady ? "ready" : "blocked",
                    "reviewedGate": reviewedExecutionGateReady ? "ready" : "blocked",
                    "audit": auditSurfaceReady ? "ready" : "blocked",
                    "localOnly": localOnly ? "true" : "false"
                ],
                blockingReasons: blockingReasons
            )
        case .missing(let reason):
            return blockedCard(phase: .localAPICLIAutomationSurface, reason: reason)
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
