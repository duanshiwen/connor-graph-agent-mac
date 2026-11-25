import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Task Run History Index")
struct TaskRunHistoryIndexTests {
    private func record(_ id: Int) -> ConnorTaskRunRecord {
        ConnorTaskRunRecord(id: "run-\(id % 31)", taskID: "task-\(id % 3)", status: .succeeded,
            startedAt: Date(timeIntervalSince1970: Double(id % 17)),
            finishedAt: id % 4 == 0 ? nil : Date(timeIntervalSince1970: Double(id % 7)), outputSummary: "record \(id)")
    }
    private func encoded(_ records: [ConnorTaskRunRecord]) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try records.reduce(into: Data()) { result, record in
            result.append(try encoder.encode(record)); result.append(10)
        }
    }
    private func repository(_ root: URL) throws -> AppTaskManagementRepository {
        let result = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        try FileManager.default.createDirectory(at: result.taskRunHistoryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return result
    }
    @Test func preservesLegacyOrderingFilteringDuplicatesAndLimits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try repository(root)
        let records = (0..<300).reversed().map(record)
        var data = try encoded(records); data.append(Data("broken json\n".utf8))
        try data.write(to: repo.taskRunHistoryURL)
        for taskID in [nil, "task-1", "missing"] as [String?] {
            let filtered = records.filter { taskID == nil || $0.taskID == taskID }
            let sorted = filtered.sorted {
                if $0.startedAt != $1.startedAt { return $0.startedAt > $1.startedAt }
                return ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast)
            }
            for limit in [0, 1, 50, 1000] {
                #expect(try repo.loadRunHistory(taskID: taskID, limit: limit) == Array(sorted.prefix(limit)))
            }
        }
        #expect(try Data(contentsOf: repo.taskRunHistoryURL) == data)
    }
    @Test func detectsExternalReplacementTruncationAndUnterminatedTail() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try repository(root)
        var initial = try encoded([record(1)]); initial.removeLast()
        try initial.write(to: repo.taskRunHistoryURL)
        #expect(try repo.loadRunHistory() == [record(1)])
        try repo.appendRunRecord(record(2))
        #expect(try repo.loadRunHistory().count == 2)
        try encoded([record(3)]).write(to: repo.taskRunHistoryURL, options: .atomic)
        #expect(try repo.loadRunHistory() == [record(3)])
        try Data().write(to: repo.taskRunHistoryURL)
        #expect(try repo.loadRunHistory().isEmpty)
        try Data("unfinished".utf8).write(to: repo.taskRunHistoryURL)
        try repo.appendRunRecord(record(4))
        #expect(try repo.loadRunHistory() == [record(4)])
    }
    @Test func corruptIndexFallsBackWithoutLosingHistoryOrAppends() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try repository(root)
        try encoded([record(1)]).write(to: repo.taskRunHistoryURL)
        try Data("not sqlite".utf8).write(to: repo.taskRunHistoryURL.appendingPathExtension("index.sqlite"))
        #expect(try repo.loadRunHistory() == [record(1)])
        try repo.appendRunRecord(record(2))
        #expect(try repo.loadRunHistory().count == 2)
    }
    @Test func concurrentAppendsPreserveEveryRecord() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try repository(root)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in 0..<100 {
                let value = record(id)
                group.addTask { try repo.appendRunRecord(value) }
            }
            try await group.waitForAll()
        }
        let all = try repo.loadRunHistory(limit: 1000)
        #expect(all.count == 100)
        #expect(Set(all.compactMap(\.outputSummary)).count == 100)
    }
    @Test func copiedLocalHistoryBenchmark() throws {
        guard let path = ProcessInfo.processInfo.environment["CONNOR_TASK_HISTORY_BENCHMARK"] else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try repository(root)
        try FileManager.default.copyItem(atPath: path, toPath: repo.taskRunHistoryURL.path)
        let start = Date()
        let first = try repo.loadRunHistory(limit: 100)
        let cold = Date().timeIntervalSince(start)
        let warmStart = Date()
        for _ in 0..<100 { #expect(try repo.loadRunHistory(limit: 100) == first) }
        print("TASK_HISTORY_BENCHMARK cold_seconds=\(cold) warm_average_seconds=\(Date().timeIntervalSince(warmStart)/100) result_count=\(first.count)")
    }
}
