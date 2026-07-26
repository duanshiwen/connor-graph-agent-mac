import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public actor PersonProfileStoreAgentContactRuntime: AgentContactRuntime {
    private let store: any PersonProfileStore
    private var drafts: [String: ContactMutationDraft] = [:]

    public init(store: any PersonProfileStore) {
        self.store = store
    }

    public func search(query: String) async throws -> [ContactRecord] {
        let profiles = try await store.searchProfiles(query: query, includeInactive: false)
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
        _ = try await store.upsert(PersonProfile(contactRecord: draft.record))
        drafts[id] = draft
        return draft
    }

    public func listPeople() async throws -> [PersonProfile] {
        try await store.loadProfiles(includeInactive: false)
    }

    public func searchPeople(query: String) async throws -> [PersonProfile] {
        try await store.searchProfiles(query: query, includeInactive: false)
    }

    public func getPerson(id: ContactID) async throws -> PersonProfile? {
        try await store.profile(id: id)
    }

    public func createPerson(_ profile: PersonProfile, approved: Bool) async throws -> PersonProfile {
        try await store.upsert(profile)
    }

    public func updatePerson(id: ContactID, update: PersonProfileDraft, approved: Bool) async throws -> PersonProfile {
        guard approved else { throw AgentToolError.permissionDenied("Person profile write approval required") }
        guard let existing = try await store.profile(id: id) else { throw AgentToolError.invalidArguments("Unknown person") }
        let updated = update.makeProfile(existing: existing)
        return try await store.upsert(updated)
    }

    public func deletePerson(id: ContactID, approved: Bool) async throws -> PersonProfile {
        guard approved else { throw AgentToolError.permissionDenied("Person profile delete approval required") }
        guard let existing = try await store.profile(id: id) else { throw AgentToolError.invalidArguments("Unknown person") }
        try await store.markDeleted(id: id, now: Date())
        var deleted = existing
        deleted.status = .deleted
        deleted.updatedAt = Date()
        return deleted
    }

    public func mergePeople(sourceID: ContactID, targetID: ContactID, approved: Bool) async throws -> PersonProfile {
        guard approved else { throw AgentToolError.permissionDenied("Person profile merge approval required") }
        do {
            return try await store.merge(sourceID: sourceID, targetID: targetID, now: Date())
        } catch SQLitePersonProfileStoreError.cannotMergeSameProfile {
            throw AgentToolError.invalidArguments("Cannot merge a person into itself")
        } catch SQLitePersonProfileStoreError.profileNotFound(let id) {
            throw AgentToolError.invalidArguments("Unknown person: \(id)")
        }
    }
}
