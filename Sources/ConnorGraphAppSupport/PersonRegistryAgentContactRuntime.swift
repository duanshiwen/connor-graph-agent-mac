import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public actor PersonRegistryAgentContactRuntime: AgentContactRuntime {
    private let profileStore: any PersonProfileStore
    private var drafts: [String: ContactMutationDraft] = [:]

    public init(profileStore: any PersonProfileStore) {
        self.profileStore = profileStore
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
        _ = try await profileStore.upsert(profile)
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
        return try await profileStore.upsert(profile)
    }

    public func updatePerson(id: ContactID, update: PersonProfileDraft, approved: Bool) async throws -> PersonProfile {
        guard approved else { throw AgentToolError.permissionDenied("Person profile write approval required") }
        guard let existing = try await profileStore.profile(id: id) else {
            throw AgentToolError.invalidArguments("Unknown person")
        }
        let updated = update.makeProfile(existing: existing)
        return try await profileStore.upsert(updated)
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
        return deleted
    }

    public func mergePeople(sourceID: ContactID, targetID: ContactID, approved: Bool) async throws -> PersonProfile {
        guard approved else { throw AgentToolError.permissionDenied("Person profile merge approval required") }
        do {
            return try await profileStore.merge(sourceID: sourceID, targetID: targetID, now: Date())
        } catch SQLitePersonProfileStoreError.cannotMergeSameProfile {
            throw AgentToolError.invalidArguments("Cannot merge a person into itself")
        } catch SQLitePersonProfileStoreError.profileNotFound(let id) {
            throw AgentToolError.invalidArguments("Unknown person: \(id)")
        }
    }
}
