import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Person Memory Binding Service Tests")
struct PersonMemoryBindingServiceTests {
    @Test func ensureBindingAssignsStableMemoryKeyToProfile() async throws {
        let sink = InMemoryPersonMemoryGovernanceSink()
        let service = AppPersonMemoryBindingService(governanceSink: sink)
        let profile = PersonProfile(id: ContactID(rawValue: "person-alice"), displayName: "Alice")

        let bound = try await service.ensureBinding(for: profile, now: Date(timeIntervalSince1970: 100))

        #expect(bound.memoryStableKey == "person-profile:person-alice")
        #expect(bound.memoryEntityID == "person:person-profile:person-alice")
        #expect(sink.events.map(\.kind) == [.bound])
        #expect(sink.events.first?.personID == profile.id)
    }

    @Test func ensureBindingDoesNotDuplicateEventWhenAlreadyBound() async throws {
        let sink = InMemoryPersonMemoryGovernanceSink()
        let service = AppPersonMemoryBindingService(governanceSink: sink)
        let profile = PersonProfile(
            id: ContactID(rawValue: "person-bound"),
            displayName: "Bound",
            memoryEntityID: "person:person-profile:person-bound",
            memoryStableKey: "person-profile:person-bound"
        )

        let bound = try await service.ensureBinding(for: profile, now: Date(timeIntervalSince1970: 100))

        #expect(bound == profile)
        #expect(sink.events.isEmpty)
    }

    @Test func mergeBindingWritesMergedIntoGovernanceStatement() async throws {
        let sink = InMemoryPersonMemoryGovernanceSink()
        let service = AppPersonMemoryBindingService(governanceSink: sink)
        let source = PersonProfile(id: ContactID(rawValue: "person-source"), displayName: "小王")
        let target = PersonProfile(id: ContactID(rawValue: "person-target"), displayName: "王诗闻")

        let boundTarget = try await service.mergeBinding(source: source, target: target, now: Date(timeIntervalSince1970: 200))

        #expect(boundTarget.memoryStableKey == "person-profile:person-target")
        #expect(sink.events.map(\.kind) == [.bound, .merged])
        #expect(sink.events.last?.personID == source.id)
        #expect(sink.events.last?.targetPersonID == target.id)
        #expect(sink.events.last?.statement.contains("小王 was merged into 王诗闻") == true)
    }

    @Test func deleteBindingWritesNotActiveRetrievalContextStatement() async throws {
        let sink = InMemoryPersonMemoryGovernanceSink()
        let service = AppPersonMemoryBindingService(governanceSink: sink)
        let profile = PersonProfile(id: ContactID(rawValue: "person-delete"), displayName: "待删除")

        try await service.markDeleted(profile: profile, now: Date(timeIntervalSince1970: 300))

        #expect(sink.events.map(\.kind) == [.deleted])
        #expect(sink.events.first?.statement.contains("deleted person") == true)
        #expect(sink.events.first?.statement.contains("not active retrieval context") == true)
    }
}
