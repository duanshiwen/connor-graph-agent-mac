import Foundation
import Observation
import ConnorGraphCore
import ConnorGraphAppSupport

@MainActor
@Observable
final class ProductOSControlFeatureModel {
    enum RegistryKind: String {
        case source
        case skill
    }

    enum Event {
        case operationSucceeded
        case operationFailed(String)
        case registryChanged(
            kind: RegistryKind,
            entryID: String,
            status: ProductOSRegistryEntryStatus,
            message: String,
            automationContext: ProductOSAutomationEventContext
        )
        case automationMatched([ProductOSAutomationTriggerRecord])
        case releaseGateChecked
    }

    var registry: ProductOSRegistrySnapshot
    var automationConfig: ProductOSAutomationConfig
    var automationTriggerRecords: [ProductOSAutomationTriggerRecord] = []
    var automationExecutionHistory: [ProductOSAutomationExecutionHistoryRecord] = []
    var commercialReleaseGateResult: CommercialReadinessReleaseGateResult?
    var message: String?

    @ObservationIgnored private let registryRepository: AppProductOSRegistryRepository?
    @ObservationIgnored private let automationRepository: AppProductOSAutomationRepository?
    @ObservationIgnored var sessionIDProvider: @MainActor () -> String = { "" }
    @ObservationIgnored var onEvent: ((Event) -> Void)?

    init(
        registry: ProductOSRegistrySnapshot = .default,
        automationConfig: ProductOSAutomationConfig = .default,
        registryRepository: AppProductOSRegistryRepository?,
        automationRepository: AppProductOSAutomationRepository?
    ) {
        self.registry = registry
        self.automationConfig = automationConfig
        self.registryRepository = registryRepository
        self.automationRepository = automationRepository
    }

    func applyStartupSnapshot(_ result: StartupDomainResult<ProductOSContentSnapshot>) {
        guard let snapshot = result.value else {
            if let failureMessage = result.failureMessage { onEvent?(.operationFailed(failureMessage)) }
            return
        }
        registry = snapshot.registry
        automationConfig = snapshot.automationConfig
        automationTriggerRecords = snapshot.triggerRecords
        automationExecutionHistory = snapshot.executionHistory
        message = "Product OS 注册表已从康纳同学 Home 加载。"
    }

    func reloadRegistry() {
        do {
            if let registryRepository {
                registry = try registryRepository.loadOrCreateDefault()
                message = "Product OS 注册表已从康纳同学 Home 加载。"
            }
            onEvent?(.operationSucceeded)
        } catch {
            onEvent?(.operationFailed(String(describing: error)))
        }
    }

    func reloadAutomation(governanceConfig: AppSessionGovernanceConfig) {
        do {
            try reloadAutomationAfterGovernanceChange(governanceConfig: governanceConfig)
            onEvent?(.operationSucceeded)
        } catch {
            onEvent?(.operationFailed(String(describing: error)))
        }
    }

    func reloadAutomationAfterGovernanceChange(governanceConfig: AppSessionGovernanceConfig) throws {
        if let automationRepository {
            automationConfig = try automationRepository.loadOrCreateDefault(governanceConfig: governanceConfig)
            automationTriggerRecords = try automationRepository.loadRecentTriggerRecords()
        }
    }

    func reloadExecutionHistory() {
        do {
            automationExecutionHistory = try automationRepository?.loadRecentExecutionHistory() ?? []
            onEvent?(.operationSucceeded)
        } catch {
            onEvent?(.operationFailed(String(describing: error)))
        }
    }

    func runCommercialReadinessReleaseGate(dashboard: CommercialReadinessDashboard) {
        let result = CommercialReadinessReleaseGate().evaluate(dashboard)
        commercialReleaseGateResult = result
        message = result.summary
        onEvent?(.releaseGateChecked)
    }

    func setAutomationRuleEnabled(
        id: String,
        isEnabled: Bool,
        governanceConfig: AppSessionGovernanceConfig
    ) {
        do {
            guard let automationRepository else { return }
            automationConfig = try automationRepository.setRuleEnabled(
                id: id,
                isEnabled: isEnabled,
                governanceConfig: governanceConfig
            )
            automationTriggerRecords = try automationRepository.loadRecentTriggerRecords()
            message = "Automation rule \(id) is now \(isEnabled ? "enabled" : "disabled")."
            onEvent?(.operationSucceeded)
        } catch {
            onEvent?(.operationFailed(String(describing: error)))
        }
    }

    func evaluateAutomation(
        _ context: ProductOSAutomationEventContext,
        governanceConfig: AppSessionGovernanceConfig
    ) {
        do {
            guard let automationRepository else { return }
            let records = try automationRepository.evaluate(context: context, governanceConfig: governanceConfig)
            guard !records.isEmpty else { return }
            automationTriggerRecords = try automationRepository.loadRecentTriggerRecords()
            onEvent?(.automationMatched(records))
        } catch {
            onEvent?(.operationFailed(String(describing: error)))
        }
    }

    func setSourceRegistryStatus(id: String, status: ProductOSRegistryEntryStatus) {
        do {
            guard let registryRepository else { return }
            registry = try registryRepository.setSourceStatus(id: id, status: status)
            let message = "Source \(id) 当前状态为 \(status.rawValue)。康纳同学仍负责凭据、权限、审计和图谱摄取治理。"
            self.message = message
            onEvent?(.registryChanged(
                kind: .source,
                entryID: id,
                status: status,
                message: message,
                automationContext: ProductOSAutomationEventContext(
                    triggerKind: .sourceRegistryChanged,
                    sessionID: sessionIDProvider(),
                    registryEntryID: id
                )
            ))
            onEvent?(.operationSucceeded)
        } catch {
            onEvent?(.operationFailed(String(describing: error)))
        }
    }

    func setSkillRegistryStatus(id: String, status: ProductOSRegistryEntryStatus) {
        do {
            guard let registryRepository else { return }
            registry = try registryRepository.setSkillStatus(id: id, status: status)
            let message = "Skill \(id) is now \(status.rawValue). Skills are instruction profiles; graph memory writes remain governed."
            self.message = message
            onEvent?(.registryChanged(
                kind: .skill,
                entryID: id,
                status: status,
                message: message,
                automationContext: ProductOSAutomationEventContext(
                    triggerKind: .skillRegistryChanged,
                    sessionID: sessionIDProvider(),
                    registryEntryID: id
                )
            ))
            onEvent?(.operationSucceeded)
        } catch {
            onEvent?(.operationFailed(String(describing: error)))
        }
    }
}
