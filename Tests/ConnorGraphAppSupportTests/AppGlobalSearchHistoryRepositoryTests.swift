import XCTest
@testable import ConnorGraphAppSupport

final class AppGlobalSearchHistoryRepositoryTests: XCTestCase {
    func testRecordSearchInsertsMostRecentFirst() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let now = Date(timeIntervalSince1970: 1_783_149_600)
        let entries = try fixture.repository.record(query: "SwiftUI search", now: now)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].query, "SwiftUI search")
        XCTAssertEqual(entries[0].normalizedQuery, "swiftui search")
        XCTAssertEqual(entries[0].searchedAt, now)
        XCTAssertEqual(entries[0].useCount, 1)
        XCTAssertEqual(try fixture.repository.load(), entries)
    }

    func testRecordSearchDeduplicatesNormalizedQueriesAndPromotesToTop() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let firstDate = Date(timeIntervalSince1970: 1_783_149_600)
        let secondDate = Date(timeIntervalSince1970: 1_783_153_200)
        _ = try fixture.repository.record(query: "Mail sync", now: firstDate)
        _ = try fixture.repository.record(query: "SwiftUI Search", now: firstDate)
        let entries = try fixture.repository.record(query: "  swiftui   search  ", now: secondDate)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].query, "swiftui search")
        XCTAssertEqual(entries[0].normalizedQuery, "swiftui search")
        XCTAssertEqual(entries[0].searchedAt, secondDate)
        XCTAssertEqual(entries[0].useCount, 2)
        XCTAssertEqual(entries[1].query, "Mail sync")
        XCTAssertEqual(entries[1].useCount, 1)
    }

    func testRecordSearchLimitsStoredHistory() throws {
        let fixture = try makeFixture(maxStoredEntries: 20)
        defer { fixture.cleanup() }

        for index in 0..<25 {
            _ = try fixture.repository.record(
                query: "query \(index)",
                now: Date(timeIntervalSince1970: TimeInterval(1_783_149_600 + index))
            )
        }

        let entries = try fixture.repository.load()
        XCTAssertEqual(entries.count, 20)
        XCTAssertEqual(entries.first?.query, "query 24")
        XCTAssertEqual(entries.last?.query, "query 5")
    }

    func testRecordSearchIgnoresBlankQueries() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let entries = try fixture.repository.record(query: "  \n  ")

        XCTAssertTrue(entries.isEmpty)
        XCTAssertTrue(try fixture.repository.load().isEmpty)
    }

    func testClearRemovesHistory() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        _ = try fixture.repository.record(query: "SwiftUI search")
        XCTAssertFalse(try fixture.repository.load().isEmpty)

        try fixture.repository.clear()

        XCTAssertTrue(try fixture.repository.load().isEmpty)
    }

    private func makeFixture(maxStoredEntries: Int = 20) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-global-search-history-\(UUID().uuidString)", isDirectory: true)
        let repository = AppGlobalSearchHistoryRepository(
            historyURL: root.appendingPathComponent("search/global-search-history.json"),
            maxStoredEntries: maxStoredEntries
        )
        return Fixture(root: root, repository: repository)
    }

    private struct Fixture {
        var root: URL
        var repository: AppGlobalSearchHistoryRepository

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
