import Foundation

public struct MediaRuntimeBootstrapProgress: Sendable, Equatable {
    public var component: String
    public var completedBytes: Int64
    public var totalBytes: Int64
    public var message: String

    public init(component: String, completedBytes: Int64 = 0, totalBytes: Int64 = 0, message: String) {
        self.component = component
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.message = message
    }

    public var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }
}

public enum MediaRuntimeBootstrapError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidResponse(String)
    case installFailed(String)

    public var description: String {
        switch self {
        case .invalidResponse(let message): "Invalid media runtime download response: \(message)"
        case .installFailed(let message): "Media runtime install failed: \(message)"
        }
    }
}

public struct MediaRuntimeBootstrapService: Sendable {
    public typealias ProgressHandler = @Sendable (MediaRuntimeBootstrapProgress) -> Void

    public struct Tool: Sendable, Equatable {
        public var id: String
        public var downloadURL: URL
        public var executableRelativePath: String
        public var version: String
        public var license: String

        public init(id: String, downloadURL: URL, executableRelativePath: String, version: String, license: String) {
            self.id = id
            self.downloadURL = downloadURL
            self.executableRelativePath = executableRelativePath
            self.version = version
            self.license = license
        }
    }

    public static let baselineTools: [Tool] = [
        Tool(
            id: "yt-dlp",
            downloadURL: URL(string: "https://github.com/yt-dlp/yt-dlp/releases/download/2026.06.09/yt-dlp_macos")!,
            executableRelativePath: "yt-dlp/runtime/yt-dlp.sh",
            version: "2026.06.09",
            license: "Unlicense"
        ),
        Tool(
            id: "ffmpeg",
            downloadURL: URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1/ffmpeg-darwin-arm64")!,
            executableRelativePath: "ffmpeg/runtime/ffmpeg",
            version: "6.1.1-static",
            license: "LGPL/GPL depending on linked codecs; see upstream ffmpeg-static release notes"
        )
    ]

    public var sidecarsDirectory: URL
    public var session: URLSession

    public init(sidecarsDirectory: URL, session: URLSession = .shared) {
        self.sidecarsDirectory = sidecarsDirectory
        self.session = session
    }

    @discardableResult
    public func ensureBaselineTools(progress: ProgressHandler? = nil) async throws -> [String] {
        try FileManager.default.createDirectory(at: sidecarsDirectory, withIntermediateDirectories: true)
        var installed: [String] = []
        for tool in Self.baselineTools {
            let executable = sidecarsDirectory.appendingPathComponent(tool.executableRelativePath)
            if FileManager.default.isExecutableFile(atPath: executable.path) {
                progress?(MediaRuntimeBootstrapProgress(component: tool.id, message: "运行时组件已就绪：\(tool.id)"))
                installed.append(tool.id)
                continue
            }
            progress?(MediaRuntimeBootstrapProgress(component: tool.id, message: "开始准备运行时组件：\(tool.id)"))
            try await downloadTool(tool, to: executable) { fileProgress in
                progress?(fileProgress)
            }
            try writeManifest(for: tool)
            installed.append(tool.id)
            progress?(MediaRuntimeBootstrapProgress(component: tool.id, message: "运行时组件已完成：\(tool.id)"))
        }
        return installed
    }

    private func downloadTool(_ tool: Tool, to executable: URL, progress: @escaping @Sendable (MediaRuntimeBootstrapProgress) -> Void) async throws {
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = executable.appendingPathExtension("partial")
        let expectedSize = try await remoteContentLength(for: tool.downloadURL)
        var existingBytes: Int64 = 0
        if let size = try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            existingBytes = Int64(size)
            if expectedSize > 0, existingBytes > expectedSize {
                try? FileManager.default.removeItem(at: partial)
                existingBytes = 0
            }
        }
        if expectedSize > 0, existingBytes == expectedSize {
            try installPartial(partial, to: executable)
            progress(MediaRuntimeBootstrapProgress(component: tool.id, completedBytes: expectedSize, totalBytes: expectedSize, message: "运行时组件已下载：\(tool.id)"))
            return
        }

        var request = URLRequest(url: tool.downloadURL)
        if existingBytes > 0 {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MediaRuntimeBootstrapError.invalidResponse("Unable to download \(tool.id)")
        }
        let shouldAppend = existingBytes > 0 && http.statusCode == 206
        if !shouldAppend {
            try? FileManager.default.removeItem(at: partial)
            existingBytes = 0
            FileManager.default.createFile(atPath: partial.path, contents: nil)
        } else if !FileManager.default.fileExists(atPath: partial.path) {
            FileManager.default.createFile(atPath: partial.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var written = existingBytes
        var buffer = Data()
        buffer.reserveCapacity(1024 * 1024)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1024 * 1024 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress(MediaRuntimeBootstrapProgress(component: tool.id, completedBytes: written, totalBytes: expectedSize, message: "正在下载运行时组件：\(tool.id)"))
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
            progress(MediaRuntimeBootstrapProgress(component: tool.id, completedBytes: written, totalBytes: expectedSize, message: "正在下载运行时组件：\(tool.id)"))
        }
        if expectedSize > 0, written != expectedSize {
            throw MediaRuntimeBootstrapError.installFailed("\(tool.id) expected \(expectedSize) bytes, got \(written)")
        }
        try handle.close()
        try installPartial(partial, to: executable)
    }

    private func remoteContentLength(for url: URL) async throws -> Int64 {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { return 0 }
        if let raw = http.value(forHTTPHeaderField: "Content-Length"), let value = Int64(raw) {
            return value
        }
        return 0
    }

    private func installPartial(_ partial: URL, to executable: URL) throws {
        if FileManager.default.fileExists(atPath: executable.path) {
            try FileManager.default.removeItem(at: executable)
        }
        try FileManager.default.moveItem(at: partial, to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableExecutable = executable
        try? mutableExecutable.setResourceValues(values)
    }

    private func writeManifest(for tool: Tool) throws {
        let manifestURL = sidecarsDirectory.appendingPathComponent(tool.id, isDirectory: true).appendingPathComponent("manifest.json")
        let descriptor = MediaRuntimeDescriptor(id: tool.id, version: tool.version, source: "app-managed-download", executableRelativePath: tool.executableRelativePath, license: tool.license)
        let data = try JSONEncoder().encode(descriptor)
        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: manifestURL, options: .atomic)
    }
}
