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
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        process.waitUntilExit()

        let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)
    }
}
