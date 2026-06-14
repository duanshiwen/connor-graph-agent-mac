import Foundation
import ConnorGraphAgent
import ConnorGraphAppSupport

struct AppCommercialReadinessDashboardBuilder {
    func build(
        chatSessions: [AgentSession],
        activeChatSession: AgentSession,
        governanceConfig: AppSessionGovernanceConfig,
        artifactDirectoriesReady: Bool,
        selectedSidecarRuntimeDiagnostics: ClaudeSDKSidecarRuntimeDiagnostics?,
        sourceRuntimeConfigurations: [MCPSourceRuntimeConfiguration],
        skillRuntimeDefinitions: [SkillRuntimeDefinition],
        automationConfig: ProductOSAutomationConfig,
        graphMemoryDashboard: GraphMemoryDashboard
    ) -> CommercialReadinessDashboard {
        let input = CommercialReadinessSnapshotBuilder().build(
            sessions: chatSessions.isEmpty ? [activeChatSession] : chatSessions,
            governanceConfig: governanceConfig,
            artifactDirectoriesReady: artifactDirectoriesReady,
            sidecarRecord: selectedSidecarRuntimeDiagnostics?.record,
            sidecarHealthStatus: selectedSidecarRuntimeDiagnostics?.health.rawValue,
            sources: sourceRuntimeConfigurations,
            skills: skillRuntimeDefinitions,
            automationConfig: automationConfig,
            graphMemoryDashboard: graphMemoryDashboard,
            shell: .default,
            settingsPanelsReady: true
        )
        return CommercialReadinessGate().evaluate(input)
    }
}
