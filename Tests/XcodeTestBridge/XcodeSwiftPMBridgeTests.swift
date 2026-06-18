import XCTest

final class XcodeSwiftPMBridgeTests: XCTestCase {
    func testSwiftPackageTestSuitePasses() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // XcodeTestBridge
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-xcode-swift-test-")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("log")
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? logHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "test"]
        process.currentDirectoryURL = packageRoot
        process.environment = sanitizedSwiftPMEnvironment()
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()

        let deadline = Date().addingTimeInterval(120)
        var observedPassingSwiftPMRun = false

        while process.isRunning, Date() < deadline {
            let output = readLog(at: logURL)
            if output.contains("Test run with ") && output.contains(" passed after ") {
                observedPassingSwiftPMRun = true
                break
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        if observedPassingSwiftPMRun {
            let gracefulExitDeadline = Date().addingTimeInterval(5)
            while process.isRunning, Date() < gracefulExitDeadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        } else {
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
        }

        let output = readLog(at: logURL)
        if observedPassingSwiftPMRun || (process.terminationStatus == 0 && output.contains("Test run with ")) {
            XCTAssertTrue(output.contains(" passed after "), output)
        } else {
            XCTAssertEqual(process.terminationStatus, 0, output)
        }
    }

    private func readLog(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func sanitizedSwiftPMEnvironment() -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        let blockedPrefixes = [
            "XCTest",
            "XCODE",
            "XCInject",
            "__XCODE",
            "LLVM_PROFILE_FILE"
        ]
        let blockedKeys: Set<String> = [
            "DYLD_INSERT_LIBRARIES",
            "NSUnbufferedIO"
        ]
        return inherited.filter { key, _ in
            !blockedKeys.contains(key) && !blockedPrefixes.contains { key.hasPrefix($0) }
        }
    }
}
