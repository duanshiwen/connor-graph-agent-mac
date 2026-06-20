import Foundation
import CryptoKit
import ConnorGraphCore

public struct MediaRuntimeDescriptor: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var version: String
    public var source: String
    public var executableRelativePath: String?
    public var checksum: String?
    public var license: String?

    public init(id: String, version: String = "unknown", source: String = "bundled", executableRelativePath: String? = nil, checksum: String? = nil, license: String? = nil) {
        self.id = id
        self.version = version
        self.source = source
        self.executableRelativePath = executableRelativePath
        self.checksum = checksum
        self.license = license
    }
}

public struct MediaRuntimeHealthReport: Sendable, Equatable {
    public var snapshot: MediaRuntimeSnapshot
    public var missingRuntimeIDs: [String]
    public var diagnostics: [String]

    public init(snapshot: MediaRuntimeSnapshot, missingRuntimeIDs: [String] = [], diagnostics: [String] = []) {
        self.snapshot = snapshot
        self.missingRuntimeIDs = missingRuntimeIDs
        self.diagnostics = diagnostics
    }

    public var isHealthy: Bool { missingRuntimeIDs.isEmpty }
}

public protocol MediaRuntimeSupervising: Sendable {
    func healthCheck(now: Date) async -> MediaRuntimeHealthReport
}

public struct MediaRuntimeSupervisor: MediaRuntimeSupervising, Sendable {
    public var sidecarsDirectory: URL

    public init(sidecarsDirectory: URL) {
        self.sidecarsDirectory = sidecarsDirectory
    }

    public func healthCheck(now: Date = Date()) async -> MediaRuntimeHealthReport {
        let python = component(id: "python", defaultExecutable: "python/runtime/bin/python3")
        let ytdlp = component(id: "yt-dlp", defaultExecutable: "yt-dlp/runtime/yt-dlp.sh")
        let ffmpeg = component(id: "ffmpeg", defaultExecutable: "ffmpeg/runtime/ffmpeg")
        let whisperKit = component(id: "whisperkit", defaultExecutable: nil)
        let missing = [python, ytdlp, ffmpeg, whisperKit].filter { !$0.isAvailable }.map(\.id)
        let diagnostics = missing.map { "Missing or unavailable media runtime: \($0)" }
        return MediaRuntimeHealthReport(
            snapshot: MediaRuntimeSnapshot(python: python, ytDLP: ytdlp, ffmpeg: ffmpeg, whisperKit: whisperKit, capturedAt: now),
            missingRuntimeIDs: missing,
            diagnostics: diagnostics
        )
    }

    private func component(id: String, defaultExecutable: String?) -> MediaRuntimeComponentSnapshot {
        let manifestURL = sidecarsDirectory
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("manifest.json")
        let manifest = try? loadDescriptor(from: manifestURL)
        let executableRelativePath = manifest?.executableRelativePath ?? defaultExecutable
        let executableURL = executableRelativePath.map { sidecarsDirectory.appendingPathComponent($0) }
        let available: Bool
        if id == "whisperkit", executableURL == nil {
            available = FileManager.default.fileExists(atPath: sidecarsDirectory.appendingPathComponent(id, isDirectory: true).path)
        } else if let executableURL {
            available = FileManager.default.isExecutableFile(atPath: executableURL.path) || FileManager.default.fileExists(atPath: executableURL.path)
        } else {
            available = FileManager.default.fileExists(atPath: sidecarsDirectory.appendingPathComponent(id, isDirectory: true).path)
        }
        let checksum = executableURL.flatMap { try? sha256Hex(forItemAt: $0) } ?? manifest?.checksum
        return MediaRuntimeComponentSnapshot(
            id: id,
            version: manifest?.version ?? "unknown",
            source: manifest?.source ?? "unresolved",
            checksum: checksum,
            isAvailable: available,
            diagnostics: available ? nil : "Runtime \(id) was not found under \(sidecarsDirectory.path)"
        )
    }

    private func loadDescriptor(from url: URL) throws -> MediaRuntimeDescriptor {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MediaRuntimeDescriptor.self, from: data)
    }

    private func sha256Hex(forItemAt url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct FakeMediaRuntimeSupervisor: MediaRuntimeSupervising, Sendable {
    public var report: MediaRuntimeHealthReport

    public init(report: MediaRuntimeHealthReport) {
        self.report = report
    }

    public func healthCheck(now: Date = Date()) async -> MediaRuntimeHealthReport {
        var copy = report
        copy.snapshot.capturedAt = now
        return copy
    }
}
