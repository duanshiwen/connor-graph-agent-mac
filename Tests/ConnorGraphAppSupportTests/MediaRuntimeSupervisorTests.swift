import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Media Runtime Supervisor Tests")
struct MediaRuntimeSupervisorTests {
    @Test func supervisorPrefersBundledRuntimeBeforeBootstrapDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appendingPathComponent("BundledMediaRuntime", isDirectory: true)
        let sidecars = root.appendingPathComponent("Sidecars", isDirectory: true)
        try FileManager.default.createDirectory(at: bundled.appendingPathComponent("yt-dlp/runtime", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundled.appendingPathComponent("ffmpeg/runtime", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundled.appendingPathComponent("python/runtime/bin", isDirectory: true), withIntermediateDirectories: true)
        try createUsableWhisperKitModel(named: "openai_whisper-small", in: bundled)
        try createUsableWhisperKitModel(named: "openai_whisper-medium", in: bundled)
        try "#!/bin/sh\n".write(to: bundled.appendingPathComponent("yt-dlp/runtime/yt-dlp.sh"), atomically: true, encoding: .utf8)
        try "binary".write(to: bundled.appendingPathComponent("ffmpeg/runtime/ffmpeg"), atomically: true, encoding: .utf8)
        try "binary".write(to: bundled.appendingPathComponent("python/runtime/bin/python3"), atomically: true, encoding: .utf8)

        let supervisor = MediaRuntimeSupervisor(sidecarsDirectory: sidecars, bundledRuntimeDirectory: bundled)
        let report = await supervisor.healthCheck(now: Date(timeIntervalSince1970: 0))

        #expect(report.isHealthy)
        #expect(report.missingRuntimeIDs.isEmpty)
        #expect(report.snapshot.ytDLP.isAvailable)
        #expect(report.snapshot.ytDLP.source == "bundled")
        #expect(report.snapshot.ffmpeg.isAvailable)
        #expect(report.snapshot.python.isAvailable)
        #expect(report.snapshot.whisperKit.isAvailable)
    }

    @Test func supervisorRequiresBothSmallAndMediumWhisperKitModels() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appendingPathComponent("BundledMediaRuntime", isDirectory: true)
        let sidecars = root.appendingPathComponent("Sidecars", isDirectory: true)
        try createUsableWhisperKitModel(named: "openai_whisper-small", in: bundled)

        let supervisor = MediaRuntimeSupervisor(sidecarsDirectory: sidecars, bundledRuntimeDirectory: bundled)
        let report = await supervisor.healthCheck(now: Date(timeIntervalSince1970: 0))

        #expect(!report.snapshot.whisperKit.isAvailable)
        #expect(report.missingRuntimeIDs.contains("whisperkit"))
        #expect(report.diagnostics.contains { $0.contains("openai_whisper-medium") })
    }

    private func createUsableWhisperKitModel(named name: String, in runtimeRoot: URL) throws {
        let directory = runtimeRoot.appendingPathComponent("whisperkit/models/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for entry in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(entry, isDirectory: true), withIntermediateDirectories: true)
        }
        try "{}".write(to: directory.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: directory.appendingPathComponent("generation_config.json"), atomically: true, encoding: .utf8)
    }
}
