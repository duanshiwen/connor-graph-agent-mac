import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Media Runtime Supervisor Tests")
struct MediaRuntimeSupervisorTests {
    @Test func supervisorReportsMissingSidecars() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let supervisor = MediaRuntimeSupervisor(sidecarsDirectory: root)

        let report = await supervisor.healthCheck(now: Date(timeIntervalSince1970: 0))

        #expect(report.isHealthy == false)
        #expect(report.missingRuntimeIDs == ["python", "yt-dlp", "ffmpeg", "whisperkit"])
        #expect(report.snapshot.python.isAvailable == false)
        #expect(report.snapshot.capturedAt == Date(timeIntervalSince1970: 0))
    }

    @Test func supervisorReadsRuntimeManifestsAndExecutablePresence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("python/runtime/bin", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("yt-dlp/runtime", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("ffmpeg/runtime", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("whisperkit", isDirectory: true), withIntermediateDirectories: true)
        try "python".write(to: root.appendingPathComponent("python/runtime/bin/python3"), atomically: true, encoding: .utf8)
        try "ytdlp".write(to: root.appendingPathComponent("yt-dlp/runtime/yt-dlp.sh"), atomically: true, encoding: .utf8)
        try "ffmpeg".write(to: root.appendingPathComponent("ffmpeg/runtime/ffmpeg"), atomically: true, encoding: .utf8)
        try writeManifest(MediaRuntimeDescriptor(id: "python", version: "3.12.0", source: "bundled", executableRelativePath: "python/runtime/bin/python3"), to: root.appendingPathComponent("python/manifest.json"))
        try writeManifest(MediaRuntimeDescriptor(id: "yt-dlp", version: "2026.06.01", source: "vendored", executableRelativePath: "yt-dlp/runtime/yt-dlp.sh"), to: root.appendingPathComponent("yt-dlp/manifest.json"))
        try writeManifest(MediaRuntimeDescriptor(id: "ffmpeg", version: "7.0-lgpl", source: "bundled", executableRelativePath: "ffmpeg/runtime/ffmpeg"), to: root.appendingPathComponent("ffmpeg/manifest.json"))
        try writeManifest(MediaRuntimeDescriptor(id: "whisperkit", version: "0.12", source: "spm"), to: root.appendingPathComponent("whisperkit/manifest.json"))

        let report = await MediaRuntimeSupervisor(sidecarsDirectory: root).healthCheck(now: Date(timeIntervalSince1970: 10))

        #expect(report.isHealthy)
        #expect(report.snapshot.python.version == "3.12.0")
        #expect(report.snapshot.ytDLP.version == "2026.06.01")
        #expect(report.snapshot.ffmpeg.version == "7.0-lgpl")
        #expect(report.snapshot.whisperKit.version == "0.12")
        #expect(report.snapshot.python.checksum?.isEmpty == false)
    }

    private func writeManifest(_ descriptor: MediaRuntimeDescriptor, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(descriptor).write(to: url)
    }
}
