import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public actor PersonRegistryAgentContactRuntime: AgentContactRuntime {
    private let profileStore: any PersonProfileStore
    private let memoryOSFacade: AppMemoryOSFacade?
    private var drafts: [String: ContactMutationDraft] = [:]

    public init(profileStore: any PersonProfileStore, memoryOSFacade: AppMemoryOSFacade? = nil) {
        self.profileStore = profileStore
        self.memoryOSFacade = memoryOSFacade
    }

    public func search(query: String) async throws -> [ContactRecord] {
        let profiles = try await profileStore.searchProfiles(query: query, includeInactive: false)
        return profiles.map(\.contactRecord)
    }

    public func createDraft(record: ContactRecord) async throws -> ContactMutationDraft {
        let draft = ContactMutationDraft(record: record)
        drafts[draft.id] = draft
        return draft
    }

    public func commitDraft(id: String, approved: Bool) async throws -> ContactMutationDraft {
        guard var draft = drafts[id] else { throw AgentToolError.invalidArguments("Unknown contact draft") }
        guard approved else { throw AgentToolError.permissionDenied("Contact write approval required") }
        draft.status = .committed
        let profile = PersonProfile(contactRecord: draft.record)
        let saved = try await profileStore.upsert(profile)
        captureInMemoryOS(saved, operation: "create")
        drafts[id] = draft
        return draft
    }

    public func listPeople() async throws -> [PersonProfile] {
        try await profileStore.loadProfiles(includeInactive: false)
    }

    public func searchPeople(query: String) async throws -> [PersonProfile] {
        try await profileStore.searchProfiles(query: query, includeInactive: false)
    }

    public func getPerson(id: ContactID) async throws -> PersonProfile? {
        try await profileStore.profile(id: id)
    }

    public func createPerson(_ profile: PersonProfile, approved: Bool) async throws -> PersonProfile {
        guard approved else { throw AgentToolError.permissionDenied("Person profile write approval required") }
        let saved = try await profileStore.upsert(profile)
        captureInMemoryOS(saved, operation: "create")
        return saved
    }

    public func updatePerson(id: ContactID, update: PersonProfileDraft, approved: Bool) async throws -> PersonProfile {
        guard approved else { throw AgentToolError.permissionDenied("Person profile write approval required") }
        guard let existing = try await profileStore.profile(id: id) else {
            throw AgentToolError.invalidArguments("Unknown person")
        }
        let updated = update.makeProfile(existing: existing)
        let saved = try await profileStore.upsert(updated)
        captureInMemoryOS(saved, operation: "update")
        return saved
    }

    public func deletePerson(id: ContactID, approved: Bool) async throws -> PersonProfile {
        guard approved else { throw AgentToolError.permissionDenied("Person profile delete approval required") }
        guard try await profileStore.profile(id: id) != nil else {
            throw AgentToolError.invalidArguments("Unknown person")
        }
        try await profileStore.markDeleted(id: id, now: Date())
        guard let deleted = try await profileStore.profile(id: id) else {
            throw AgentToolError.invalidArguments("Unknown person")
        }
        captureInMemoryOS(deleted, operation: "delete")
        return deleted
    }

    public func mergePeople(sourceID: ContactID, targetID: ContactID, approved: Bool) async throws -> PersonProfile {
        guard approved else { throw AgentToolError.permissionDenied("Person profile merge approval required") }
        do {
            let merged = try await profileStore.merge(sourceID: sourceID, targetID: targetID, now: Date())
            captureInMemoryOS(
                merged,
                operation: "merge",
                metadata: ["merged_source_person_id": sourceID.rawValue, "merged_target_person_id": targetID.rawValue]
            )
            return merged
        } catch SQLitePersonProfileStoreError.cannotMergeSameProfile {
            throw AgentToolError.invalidArguments("Cannot merge a person into itself")
        } catch SQLitePersonProfileStoreError.profileNotFound(let id) {
            throw AgentToolError.invalidArguments("Unknown person: \(id)")
        }
    }

    private func captureInMemoryOS(_ profile: PersonProfile, operation: String, metadata: [String: String] = [:]) {
        guard let memoryOSFacade else { return }
        var lines = [
            "Person Registry operation: \(operation)",
            "Person ID: \(profile.id.rawValue)",
            "Display name: \(profile.displayName)",
            "Status: \(profile.status.rawValue)"
        ]
        if !profile.aliases.isEmpty { lines.append("Aliases: \(profile.aliases.joined(separator: ", "))") }
        if let organization = nonEmpty(profile.organizationName) { lines.append("Organization: \(organization)") }
        if let jobTitle = nonEmpty(profile.jobTitle) { lines.append("Job title: \(jobTitle)") }
        if let notes = nonEmpty(profile.notes) { lines.append("Notes: \(notes)") }

        _ = try? memoryOSFacade.ingestSourceEvent(
            sourceID: "person_registry:\(profile.id.rawValue):\(operation):\(Int(profile.updatedAt.timeIntervalSince1970 * 1_000))",
            title: "Person Registry profile: \(profile.displayName)",
            content: lines.joined(separator: "\n"),
            occurredAt: profile.updatedAt,
            sourceKind: "person_registry",
            metadata: metadata.merging([
                "person_profile_id": profile.id.rawValue,
                "person_profile_status": profile.status.rawValue,
                "person_registry_operation": operation
            ]) { current, _ in current }
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
