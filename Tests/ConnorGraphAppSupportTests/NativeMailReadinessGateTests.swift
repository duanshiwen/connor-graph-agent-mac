import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Native Mail Readiness Gate Tests")
struct NativeMailReadinessGateTests {
    @Test func nativeMailReadinessBlocksWhenSMTPOrDraftStoreUnavailable() {
        let dashboard = CommercialReadinessGate().evaluate(CommercialReadinessInput(
            sessionGovernance: .ready(sessionCount: 1, statusDefinitionCount: 5, labelDefinitionCount: 5, artifactDirectoriesReady: true),
            modelProvider: .ready(providerMode: .anthropicMessages, connectionKind: .anthropicCompatible, modelID: "test", healthStatus: "ready"),
            extensionRuntime: .ready(enabledSourceCount: 1, loadedSkillCount: 1, enabledAutomationRuleCount: 1),
            graphMemory: .ready(pendingCandidateCount: 0, openHoldCount: 0, recentChangeCount: 0, contextReady: true, ingestionReady: true, distillationReady: true),
            nativeUI: .ready(shellItemCount: 13, commandCount: 12, settingsPanelsReady: true, homeSurfaceReady: true, readinessDashboardLinked: true, primaryActionCount: 7, emptyStateCount: 4, keyboardShortcutCount: 10, settingsSectionCount: 7),
            nativeMailSystem: .ready(accountCount: 1, healthyAccountCount: 1, credentialBoundaryReady: true, syncCursorReady: true, toolAuditReady: true, sendApprovalReady: true, smtpSendAdapterReady: false, persistentDraftStoreReady: false, contactApprovalReady: true, attachmentImportReady: true, evidencePolicyReady: true)
        ))
        let card = try! #require(dashboard.cards.first { $0.phase == .nativeMailSystem })
        #expect(card.status == .blocked)
        #expect(card.blockingReasons.contains("SMTP send adapter is not ready"))
        #expect(card.blockingReasons.contains("Persistent mail draft store is not ready"))
        #expect(card.metrics["smtpSendAdapter"] == "blocked")
        #expect(card.metrics["persistentDraftStore"] == "blocked")
    }
}
