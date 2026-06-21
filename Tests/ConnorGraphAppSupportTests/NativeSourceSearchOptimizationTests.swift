import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Native Source Search Optimization Tests")
struct NativeSourceSearchOptimizationTests {
    @Test func searchLimitPolicyClampsInvalidAndOversizedValues() {
        #expect(NativeSearchLimitPolicy.clampSearchLimit(-5) == NativeSearchLimitPolicy.defaultSearchLimit)
        #expect(NativeSearchLimitPolicy.clampSearchLimit(0) == NativeSearchLimitPolicy.defaultSearchLimit)
        #expect(NativeSearchLimitPolicy.clampSearchLimit(10_000) == NativeSearchLimitPolicy.maxSearchLimit)
        #expect(NativeSearchQuery(text: "", limit: -1).limit == NativeSearchLimitPolicy.defaultSearchLimit)
        #expect(NativeSearchQuery(text: "", limit: 10_000).limit == NativeSearchLimitPolicy.maxSearchLimit)
    }

    @Test func stableHashIsDeterministicAndNotSwiftProcessHashValue() {
        let value = "subject|snippet|body|2026-06-21|false"

        let first = NativeSourceSearchAdapters.stableHash(value)
        let second = NativeSourceSearchAdapters.stableHash(value)

        #expect(first == second)
        #expect(first == "7e4043c09cc88d7a")
        #expect(first != String(value.hashValue))
    }

    @Test func noOpUpsertDoesNotRewritePersistentIndex() async throws {
        try await assertNoOpUpsertDoesNotRewritePersistentIndex(includeIndexedAt: true)
    }

    @Test func noOpUpsertWithoutIndexedAtPreservesExistingIndexedTimeAndDoesNotRewrite() async throws {
        try await assertNoOpUpsertDoesNotRewritePersistentIndex(includeIndexedAt: false)
    }

    private func assertNoOpUpsertDoesNotRewritePersistentIndex(includeIndexedAt: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-search-optimization-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let indexURL = directory.appendingPathComponent("native-source-index.json")
        let service = NativeSourceSearchService(indexURL: indexURL)
        let indexedAt = includeIndexedAt ? Date(timeIntervalSince1970: 1_780_000_100) : nil
        let document = NativeSearchDocument(
            id: "mail:1",
            sourceKind: .mail,
            sourceInstanceID: "account-1",
            externalID: "1",
            title: "Quarterly planning",
            summary: "Planning notes",
            temporal: NativeSearchTemporalMetadata(primaryTime: Date(timeIntervalSince1970: 1_780_000_000), primaryTimeKind: .sentAt, sentAt: Date(timeIntervalSince1970: 1_780_000_000), indexedAt: indexedAt),
            contentHash: "stable"
        )

        try await service.upsert([document])
        let firstAttributes = try FileManager.default.attributesOfItem(atPath: indexURL.path)
        let firstModification = try #require(firstAttributes[.modificationDate] as? Date)
        try await Task.sleep(nanoseconds: 1_100_000_000)

        try await service.upsert([document])
        let secondAttributes = try FileManager.default.attributesOfItem(atPath: indexURL.path)
        let secondModification = try #require(secondAttributes[.modificationDate] as? Date)

        #expect(secondModification == firstModification)
    }
}
