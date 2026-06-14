import Foundation
import ConnorGraphAgent

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

        let nativePresentation = ConnorNativeCommercialUIPresentation.build(shell: shell)
        let nativeUI = CommercialNativeUIReadiness.ready(
            shellItemCount: shell.sidebarGroups.flatMap(\.items).count,
            commandCount: shell.commands.count,
            settingsPanelsReady: settingsPanelsReady,
            homeSurfaceReady: shell.item(for: shell.defaultSelection) != nil,
            commandPaletteReady: !shell.commands.isEmpty,
            readinessDashboardLinked: shell.command(for: .checkCommercialReadiness) != nil,
            primaryActionCount: shell.commands.filter(\.isPrimaryAction).count,
            emptyStateCount: shell.sidebarGroups.flatMap(\.items).filter { $0.emptyStateTitle != nil }.count,
            keyboardShortcutCount: shell.commands.filter { $0.keyboardShortcut != nil }.count,
            settingsSectionCount: nativePresentation.settings.sections.count
        )

        let localAutomationSurfacePresentation = ConnorLocalAutomationSurfacePresentation.default
        let localAutomationSurface = CommercialLocalAutomationSurfaceReadiness.ready(
            endpointCount: localAutomationSurfacePresentation.endpoints.count,
            cliCommandCount: localAutomationSurfacePresentation.cliCommands.count,
            automationTriggerCount: localAutomationSurfacePresentation.supportedTriggers.count,
            dryRunEvaluationReady: localAutomationSurfacePresentation.dryRunEvaluationReady,
            reviewedExecutionGateReady: localAutomationSurfacePresentation.reviewedExecutionGateReady,
            auditSurfaceReady: localAutomationSurfacePresentation.auditSurfaceReady,
            localOnly: localAutomationSurfacePresentation.localOnly
        )

        return CommercialReadinessInput(
            sessionGovernance: sessionGovernance,
            claudeSidecar: claudeSidecar,
            extensionRuntime: extensionRuntime,
            graphMemory: graphMemory,
            nativeUI: nativeUI,
            localAutomationSurface: localAutomationSurface
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

