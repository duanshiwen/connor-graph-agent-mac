import Foundation
import Observation
import ConnorGraphCore
import ConnorGraphAppSupport

@MainActor
@Observable
final class GovernanceFeatureModel {
    private(set) var config: AppSessionGovernanceConfig
    private(set) var errorMessage: String?

    @ObservationIgnored private let repository: AppSessionGovernanceConfigRepository?
    @ObservationIgnored var sessionsProvider: () throws -> [AgentSession] = { [] }
    @ObservationIgnored var removeLabelFromSessions: (String) throws -> Int = { _ in 0 }
    @ObservationIgnored var onConfigSaved: (AppSessionGovernanceConfig) throws -> Void = { _ in }
    @ObservationIgnored var onSettingsMessage: (String, ConnorSettingsSection) -> Void = { _, _ in }
    @ObservationIgnored var onDefinitionDeleted: (GovernanceDefinitionDeletion) -> Void = { _ in }
    @ObservationIgnored var onError: (String) -> Void = { _ in }

    init(
        config: AppSessionGovernanceConfig = .default,
        repository: AppSessionGovernanceConfigRepository? = nil
    ) {
        self.config = config
        self.repository = repository
    }

    func apply(_ config: AppSessionGovernanceConfig) {
        self.config = AppSessionGovernanceConfig(statuses: config.statuses, labels: config.labels)
    }

    func upsertStatus(_ definition: AgentSessionStatusDefinition) {
        var next = config
        let trimmedID = definition.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedID.isEmpty, let index = next.statuses.firstIndex(where: { $0.id == trimmedID }) {
            var updated = definition
            updated.id = trimmedID
            next.statuses[index] = updated
        } else {
            var created = definition
            created.id = makeUniqueSlug(
                existingIDs: Set(next.statuses.map(\.id)),
                prefix: "status",
                preferredName: definition.name
            )
            next.statuses.append(created)
        }
        save(next, successMessage: "状态定义已保存。", section: .statuses)
    }

    func canDeleteStatus(_ definition: AgentSessionStatusDefinition) -> Bool {
        guard config.statuses.count > 1 else { return false }
        let sessions = (try? sessionsProvider()) ?? []
        return !sessions.contains { $0.governance.status.rawValue == definition.id }
    }

    func deleteStatus(_ definition: AgentSessionStatusDefinition) {
        guard config.statuses.count > 1 else {
            setError("至少需要保留一个状态。")
            return
        }
        do {
            let sessionsUsingStatus = try sessionsProvider().filter {
                $0.governance.status.rawValue == definition.id
            }
            guard sessionsUsingStatus.isEmpty else {
                setError("无法删除状态“\(definition.name)”: 仍有 \(sessionsUsingStatus.count) 个会话处于此状态。")
                return
            }
            var next = config
            next.statuses.removeAll { $0.id == definition.id }
            guard save(next, successMessage: "状态“\(definition.name)”已删除。", section: .statuses) else { return }
            onDefinitionDeleted(.status(definition.id))
        } catch {
            setError(String(describing: error))
        }
    }

    func upsertLabel(_ definition: AgentSessionLabelDefinition) {
        var next = config
        let trimmedID = definition.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedID.isEmpty, let index = next.labels.firstIndex(where: { $0.id == trimmedID }) {
            var updated = definition
            updated.id = trimmedID
            next.labels[index] = updated
        } else {
            var created = definition
            created.id = makeUniqueSlug(
                existingIDs: Set(next.labels.map(\.id)),
                prefix: "label",
                preferredName: definition.name
            )
            next.labels.append(created)
        }
        save(next, successMessage: "标签定义已保存。", section: .labels)
    }

    func deleteLabel(_ definition: AgentSessionLabelDefinition) {
        do {
            let removedCount = try removeLabelFromSessions(definition.id)
            var next = config
            next.labels.removeAll { $0.id == definition.id }
            guard save(
                next,
                successMessage: "标签“\(definition.name)”已删除，并已从 \(removedCount) 个会话移除。",
                section: .labels
            ) else { return }
            onDefinitionDeleted(.label(definition.id))
        } catch {
            setError(String(describing: error))
        }
    }

    @discardableResult
    private func save(
        _ next: AppSessionGovernanceConfig,
        successMessage: String,
        section: ConnorSettingsSection
    ) -> Bool {
        do {
            let normalized = AppSessionGovernanceConfig(statuses: next.statuses, labels: next.labels)
            try repository?.save(normalized)
            config = normalized
            try onConfigSaved(normalized)
            onSettingsMessage(successMessage, section)
            errorMessage = nil
            return true
        } catch {
            setError(String(describing: error))
            return false
        }
    }

    private func setError(_ message: String) {
        errorMessage = message
        onError(message)
    }

    private func makeUniqueSlug(existingIDs: Set<String>, prefix: String, preferredName: String) -> String {
        let allowedScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        let slug = preferredName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .unicodeScalars
            .map { allowedScalars.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" { return }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .replacingOccurrences(of: "-", with: "_")
        let base = slug.isEmpty ? "\(prefix)_\(shortIDFragment())" : slug
        var candidate = base
        var suffix = 2
        while existingIDs.contains(candidate) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func shortIDFragment() -> String {
        String(UUID().uuidString.lowercased().prefix(8))
    }
}

enum GovernanceDefinitionDeletion: Sendable, Equatable {
    case status(String)
    case label(String)
}
