import Foundation
import ConnorGraphCore
import ConnorGraphAgent

public enum CommercialReadinessPhase: String, Codable, Sendable, Equatable, Hashable, Identifiable, CaseIterable {
    case sessionGovernance
    case nativeModelProviders
    case sourcesSkillsAutomations
    case graphMemoryLoop
    case nativeCommercialUI
    case nativeMailSystem
    case localAPICLIAutomationSurface
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sessionGovernance: "Phase 1 · Session Governance"
        case .nativeModelProviders: "Phase 2 · Native Model Providers"
        case .sourcesSkillsAutomations: "Phase 3 · Sources / Skills / Automations"
        case .graphMemoryLoop: "Phase 4 · Graph Memory Loop"
        case .nativeCommercialUI: "Phase 5 · Native Commercial UI"
        case .nativeMailSystem: "Phase 7 · Native Mail Data Source"
        case .localAPICLIAutomationSurface: "Phase 6 · Local API / CLI / Automation Surface"
        }
    }

    public var target: ConnorNativeShellItem {
        switch self {
        case .sessionGovernance: .agentChat
        case .nativeModelProviders: .settings
        case .sourcesSkillsAutomations: .sources
        case .graphMemoryLoop: .graphMemory
        case .nativeCommercialUI: .settings
        case .nativeMailSystem: .mail
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

public enum CommercialModelProviderReadiness: Codable, Sendable, Equatable {
    case ready(
        providerMode: AppLLMProviderMode,
        connectionKind: AppLLMConnectionKind,
        modelID: String,
        healthStatus: String,
        supportsToolCalling: Bool = true,
        supportsStreaming: Bool = true,
        nativeRuntime: Bool = true
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

public enum CommercialNativeMailSystemReadiness: Codable, Sendable, Equatable {
    case ready(
        accountCount: Int,
        healthyAccountCount: Int,
        credentialBoundaryReady: Bool,
        syncCursorReady: Bool,
        toolAuditReady: Bool,
        sendApprovalReady: Bool,
        smtpSendAdapterReady: Bool,
        persistentDraftStoreReady: Bool,
        contactApprovalReady: Bool,
        attachmentImportReady: Bool,
        evidencePolicyReady: Bool
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
    public var modelProvider: CommercialModelProviderReadiness
    public var extensionRuntime: CommercialExtensionRuntimeReadiness
    public var graphMemory: CommercialGraphMemoryReadiness
    public var nativeUI: CommercialNativeUIReadiness
    public var nativeMailSystem: CommercialNativeMailSystemReadiness
    public var localAutomationSurface: CommercialLocalAutomationSurfaceReadiness

    public init(
        sessionGovernance: CommercialSessionGovernanceReadiness,
        modelProvider: CommercialModelProviderReadiness,
        extensionRuntime: CommercialExtensionRuntimeReadiness,
        graphMemory: CommercialGraphMemoryReadiness,
        nativeUI: CommercialNativeUIReadiness,
        nativeMailSystem: CommercialNativeMailSystemReadiness = .ready(accountCount: 1, healthyAccountCount: 1, credentialBoundaryReady: true, syncCursorReady: true, toolAuditReady: true, sendApprovalReady: true, smtpSendAdapterReady: true, persistentDraftStoreReady: true, contactApprovalReady: true, attachmentImportReady: true, evidencePolicyReady: true),
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
        self.modelProvider = modelProvider
        self.extensionRuntime = extensionRuntime
        self.graphMemory = graphMemory
        self.nativeUI = nativeUI
        self.nativeMailSystem = nativeMailSystem
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
            modelProviderCard(input.modelProvider),
            extensionRuntimeCard(input.extensionRuntime),
            graphMemoryCard(input.graphMemory),
            nativeUICard(input.nativeUI),
            localAutomationSurfaceCard(input.localAutomationSurface),
            nativeMailSystemCard(input.nativeMailSystem),
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

    private func modelProviderCard(_ readiness: CommercialModelProviderReadiness) -> CommercialReadinessCard {
        switch readiness {
        case .ready(
            let providerMode,
            let connectionKind,
            let modelID,
            let healthStatus,
            let supportsToolCalling,
            let supportsStreaming,
            let nativeRuntime
        ):
            let blockedReasons = [
                nativeRuntime ? nil : "Model provider must run through Connor-native runtime",
                supportsToolCalling ? nil : "Model provider must support Connor tool calling",
                supportsStreaming ? nil : "Model provider should support streaming events"
            ].compactMap { $0 }
            return CommercialReadinessCard(
                phase: .nativeModelProviders,
                status: blockedReasons.isEmpty ? .ready : .blocked,
                evidence: "provider \(providerMode.rawValue) · connection \(connectionKind.rawValue) · model \(modelID) · health \(healthStatus) · native \(nativeRuntime ? "yes" : "no")",
                metrics: [
                    "providerMode": providerMode.rawValue,
                    "connectionKind": connectionKind.rawValue,
                    "model": modelID,
                    "health": healthStatus,
                    "toolCalling": supportsToolCalling ? "supported" : "missing",
                    "streaming": supportsStreaming ? "supported" : "missing",
                    "runtime": nativeRuntime ? "Connor-native" : "external"
                ],
                blockingReasons: blockedReasons
            )
        case .missing(let reason):
            return blockedCard(phase: .nativeModelProviders, reason: reason)
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

    private func nativeMailSystemCard(_ readiness: CommercialNativeMailSystemReadiness) -> CommercialReadinessCard {
        switch readiness {
        case .ready(
            let accountCount,
            let healthyAccountCount,
            let credentialBoundaryReady,
            let syncCursorReady,
            let toolAuditReady,
            let sendApprovalReady,
            let smtpSendAdapterReady,
            let persistentDraftStoreReady,
            let contactApprovalReady,
            let attachmentImportReady,
            let evidencePolicyReady
        ):
            let blockingReasons = [
                accountCount > 0 ? nil : "No mail accounts are configured",
                healthyAccountCount > 0 ? nil : "No healthy mail accounts are available",
                credentialBoundaryReady ? nil : "Mail credential boundary is not ready",
                syncCursorReady ? nil : "Mail sync cursor is not ready",
                toolAuditReady ? nil : "Mail tool audit log is not ready",
                sendApprovalReady ? nil : "Mail send approval bridge is not ready",
                smtpSendAdapterReady ? nil : "SMTP send adapter is not ready",
                persistentDraftStoreReady ? nil : "Persistent mail draft store is not ready",
                contactApprovalReady ? nil : "Mail contact approval path is not ready",
                attachmentImportReady ? nil : "Mail attachment import path is not ready",
                evidencePolicyReady ? nil : "Mail evidence policy is not ready"
            ].compactMap { $0 }
            return CommercialReadinessCard(
                phase: .nativeMailSystem,
                status: blockingReasons.isEmpty ? .ready : .blocked,
                evidence: "\(accountCount) accounts · \(healthyAccountCount) healthy · credentials \(credentialBoundaryReady ? "ready" : "blocked") · sync \(syncCursorReady ? "ready" : "blocked") · approval \(sendApprovalReady ? "ready" : "blocked") · SMTP \(smtpSendAdapterReady ? "ready" : "blocked")",
                metrics: [
                    "accounts": "\(accountCount)",
                    "healthyAccounts": "\(healthyAccountCount)",
                    "credentials": credentialBoundaryReady ? "ready" : "blocked",
                    "syncCursor": syncCursorReady ? "ready" : "blocked",
                    "toolAudit": toolAuditReady ? "ready" : "blocked",
                    "sendApproval": sendApprovalReady ? "ready" : "blocked",
                    "smtpSendAdapter": smtpSendAdapterReady ? "ready" : "blocked",
                    "persistentDraftStore": persistentDraftStoreReady ? "ready" : "blocked",
                    "contactApproval": contactApprovalReady ? "ready" : "blocked",
                    "attachmentImport": attachmentImportReady ? "ready" : "blocked",
                    "evidencePolicy": evidencePolicyReady ? "ready" : "blocked"
                ],
                blockingReasons: blockingReasons
            )
        case .missing(let reason):
            return blockedCard(phase: .nativeMailSystem, reason: reason)
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
