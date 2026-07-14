import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
struct ProductOSControlFeatureModelTests {
    @Test func reloadsRegistryAutomationAndExecutionHistory() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let history = ProductOSAutomationExecutionHistoryRecord(
            sessionID: "session-history",
            trigger: .sessionLabelAdded,
            ruleIDs: ["important-label-adds-review-note"],
            appliedActionCount: 1,
            skippedActionCount: 0,
            eventCount: 1,
            outcome: .completed,
            message: "completed"
        )
        try fixture.automationRepository.appendExecutionHistory(history)
        let model = makeModel(fixture)

        model.reloadRegistry()
        model.reloadAutomation(governanceConfig: .default)
        model.reloadExecutionHistory()

        #expect(model.registry.sources.isEmpty == false)
        #expect(model.registry.skills.isEmpty == false)
        #expect(model.automationConfig.rules.contains(where: { $0.id == "important-label-adds-review-note" }))
        #expect(model.automationExecutionHistory.map(\.id) == [history.id])
        #expect(model.message == "Product OS 注册表已从康纳同学 Home 加载。")
    }

    @Test func ruleToggleAndAutomationEvaluationUpdateSingleStateSource() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(fixture)
        model.reloadAutomation(governanceConfig: .default)
        var matched: [ProductOSAutomationTriggerRecord] = []
        model.onEvent = { event in
            if case .automationMatched(let records) = event {
                matched = records
            }
        }

        model.setAutomationRuleEnabled(
            id: "important-label-adds-review-note",
            isEnabled: false,
            governanceConfig: .default
        )
        #expect(model.automationConfig.rules.first(where: { $0.id == "important-label-adds-review-note" })?.isEnabled == false)
        #expect(model.message == "Automation rule important-label-adds-review-note is now disabled.")

        model.setAutomationRuleEnabled(
            id: "important-label-adds-review-note",
            isEnabled: true,
            governanceConfig: .default
        )
        model.evaluateAutomation(
            ProductOSAutomationEventContext(
                triggerKind: .sessionLabelAdded,
                sessionID: "session-match",
                labelID: "important"
            ),
            governanceConfig: .default
        )

        #expect(matched.map(\.ruleID) == ["important-label-adds-review-note"])
        #expect(model.automationTriggerRecords.map(\.sessionID) == ["session-match"])
    }

    @Test func registryMutationsEmitNarrowEventsWithCurrentSession() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(fixture)
        model.reloadRegistry()
        model.sessionIDProvider = { "session-current" }
        var registryKinds: [ProductOSControlFeatureModel.RegistryKind] = []
        var contexts: [ProductOSAutomationEventContext] = []
        model.onEvent = { event in
            if case .registryChanged(let kind, _, _, _, let context) = event {
                registryKinds.append(kind)
                contexts.append(context)
            }
        }
        let source = try #require(model.registry.sources.first)
        let skill = try #require(model.registry.skills.first)

        model.setSourceRegistryStatus(id: source.id, status: .enabled)
        model.setSkillRegistryStatus(id: skill.id, status: .enabled)

        #expect(registryKinds == [.source, .skill])
        #expect(contexts.map(\.sessionID) == ["session-current", "session-current"])
        #expect(contexts.map(\.registryEntryID) == [source.id, skill.id])
        #expect(model.registry.sources.first(where: { $0.id == source.id })?.status == .enabled)
        #expect(model.registry.skills.first(where: { $0.id == skill.id })?.status == .enabled)
    }

    @Test func releaseGateStoresResultMessageAndNavigationIntent() {
        let model = ProductOSControlFeatureModel(
            registryRepository: nil,
            automationRepository: nil
        )
        let dashboard = CommercialReadinessDashboard(cards: CommercialReadinessPhase.allCases.map {
            CommercialReadinessCard(phase: $0, status: .ready, evidence: "ready")
        })
        var requestedNavigation = false
        model.onEvent = { event in
            if case .releaseGateChecked = event {
                requestedNavigation = true
            }
        }

        model.runCommercialReadinessReleaseGate(dashboard: dashboard)

        #expect(model.commercialReleaseGateResult?.status == .ready)
        #expect(model.message == "READY · 7/7 commercial readiness phases ready")
        #expect(requestedNavigation)
    }

    private func makeFixture() throws -> (
        root: URL,
        registryRepository: AppProductOSRegistryRepository,
        automationRepository: AppProductOSAutomationRepository
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-product-os-control-model-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
        try paths.ensureDirectoryHierarchy(fileManager: .default)
        return (
            root,
            AppProductOSRegistryRepository(storagePaths: paths),
            AppProductOSAutomationRepository(storagePaths: paths)
        )
    }

    private func makeModel(_ fixture: (
        root: URL,
        registryRepository: AppProductOSRegistryRepository,
        automationRepository: AppProductOSAutomationRepository
    )) -> ProductOSControlFeatureModel {
        ProductOSControlFeatureModel(
            registryRepository: fixture.registryRepository,
            automationRepository: fixture.automationRepository
        )
    }
}
