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
    public var bundledRuntimeDirectory: URL?

    public init(sidecarsDirectory: URL, bundledRuntimeDirectory: URL? = MediaRuntimeSupervisor.defaultBundledRuntimeDirectory()) {
        self.sidecarsDirectory = sidecarsDirectory
        self.bundledRuntimeDirectory = bundledRuntimeDirectory
    }

    public func healthCheck(now: Date = Date()) async -> MediaRuntimeHealthReport {
        let python = component(id: "python", defaultExecutable: "python/runtime/bin/python3")
        let ytdlp = component(id: "yt-dlp", defaultExecutable: "yt-dlp/runtime/yt-dlp.sh")
        let ffmpeg = component(id: "ffmpeg", defaultExecutable: "ffmpeg/runtime/ffmpeg")
        let whisperKit = component(id: "whisperkit", defaultExecutable: nil)
        let components = [python, ytdlp, ffmpeg, whisperKit]
        let missing = components.filter { !$0.isAvailable }.map(\.id)
        let diagnostics = components.compactMap(\.diagnostics)
        return MediaRuntimeHealthReport(
            snapshot: MediaRuntimeSnapshot(python: python, ytDLP: ytdlp, ffmpeg: ffmpeg, whisperKit: whisperKit, capturedAt: now),
            missingRuntimeIDs: missing,
            diagnostics: diagnostics
        )
    }

    public static func defaultBundledRuntimeDirectory(bundle: Bundle = .main) -> URL? {
        if let url = bundle.url(forResource: "MediaRuntime", withExtension: nil), FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let resourceURL = bundle.resourceURL {
            let candidate = resourceURL.appendingPathComponent("MediaRuntime", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func component(id: String, defaultExecutable: String?) -> MediaRuntimeComponentSnapshot {
        let installation = resolveComponent(id: id, defaultExecutable: defaultExecutable)
        let manifest = installation.manifest
        let executableURL = installation.executableURL
        let available: Bool
        if id == "whisperkit", executableURL == nil {
            available = FileManager.default.fileExists(atPath: installation.rootDirectory.appendingPathComponent(id, isDirectory: true).path)
        } else if let executableURL {
            available = FileManager.default.isExecutableFile(atPath: executableURL.path) || FileManager.default.fileExists(atPath: executableURL.path)
        } else {
            available = FileManager.default.fileExists(atPath: installation.rootDirectory.appendingPathComponent(id, isDirectory: true).path)
        }
        let checksum = executableURL.flatMap { try? sha256Hex(forItemAt: $0) } ?? manifest?.checksum
        let source = manifest?.source ?? installation.source
        return MediaRuntimeComponentSnapshot(
            id: id,
            version: manifest?.version ?? "app-managed",
            source: source,
            checksum: checksum,
            isAvailable: available,
            diagnostics: available ? nil : "App-managed media runtime component \(id) is not ready. Checked bundled runtime and bootstrap directory under \(sidecarsDirectory.path)."
        )
    }

    private func resolveComponent(id: String, defaultExecutable: String?) -> (rootDirectory: URL, source: String, manifest: MediaRuntimeDescriptor?, executableURL: URL?) {
        let roots: [(URL, String)] = ([bundledRuntimeDirectory.map { ($0, "bundled") }].compactMap { $0 }) + [(sidecarsDirectory, "bootstrapped")]
        for (root, source) in roots {
            let manifestURL = root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("manifest.json")
            let manifest = try? loadDescriptor(from: manifestURL)
            let executableRelativePath = manifest?.executableRelativePath ?? defaultExecutable
            let executableURL = executableRelativePath.map { root.appendingPathComponent($0) }
            if let executableURL, FileManager.default.fileExists(atPath: executableURL.path) {
                return (root, source, manifest, executableURL)
            }
            if id == "whisperkit", FileManager.default.fileExists(atPath: root.appendingPathComponent(id, isDirectory: true).path) {
                return (root, source, manifest, executableURL)
            }
            if manifest != nil {
                return (root, source, manifest, executableURL)
            }
        }
        return (sidecarsDirectory, "app-managed", nil, defaultExecutable.map { sidecarsDirectory.appendingPathComponent($0) })
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
