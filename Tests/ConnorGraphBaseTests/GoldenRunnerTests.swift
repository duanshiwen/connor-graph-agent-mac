import XCTest
import Foundation
@testable import ConnorGraphBase

/// M1-K8：golden 全量执行器——跑 M0-3 首批 20 条 fixture，逐条比对契约 envelope。
final class GoldenRunnerTests: XCTestCase {

    func testAllGoldenFixtures() throws {
        let goldenURL = Bundle.module.resourceURL!
            .appendingPathComponent("Golden", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: goldenURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertEqual(files.count, 20, "golden fixture 数量应为 20（M0 首批）")

        var failures: [String] = []
        var passed: [String] = []
        for file in files {
            let data = try Data(contentsOf: file)
            let fixture = try JSONDecoder().decode(BaseGoldenRunner.Fixture.self, from: data)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("base-golden-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }

            do {
                let actual = try BaseGoldenRunner.execute(fixture, in: tmp)
                if let failure = BaseGoldenRunner.compare(actual: actual, expected: fixture.then) {
                    failures.append("\(file.lastPathComponent): \(failure)")
                } else {
                    passed.append(file.lastPathComponent)
                }
            } catch {
                failures.append("\(file.lastPathComponent): 执行抛错 \(error)")
            }
        }
        XCTAssertTrue(failures.isEmpty,
                      "golden 失败 \(failures.count) 条：\n---\n" + failures.joined(separator: "\n---\n"))
        print("golden 通过：\(passed.joined(separator: ", "))")
    }
}
