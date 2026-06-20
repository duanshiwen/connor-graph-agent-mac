import Foundation

public struct WhisperKitModelBootstrapProgress: Sendable, Equatable {
    public var model: String
    public var filePath: String
    public var completedBytes: Int64
    public var totalBytes: Int64
    public var message: String

    public init(model: String, filePath: String = "", completedBytes: Int64 = 0, totalBytes: Int64 = 0, message: String) {
        self.model = model
        self.filePath = filePath
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.message = message
    }

    public var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }
}

public enum WhisperKitModelBootstrapError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidModel(String)
    case invalidAPIResponse(String)
    case incompleteModel(String, missing: [String])
    case downloadFailed(String)

    public var description: String {
        switch self {
        case .invalidModel(let model): "Unsupported WhisperKit baseline model: \(model)"
        case .invalidAPIResponse(let message): "Invalid WhisperKit model API response: \(message)"
        case .incompleteModel(let model, let missing): "WhisperKit model \(model) is incomplete; missing \(missing.joined(separator: ", "))"
        case .downloadFailed(let message): "WhisperKit model download failed: \(message)"
        }
    }
}

public struct WhisperKitModelBootstrapService: Sendable {
    public typealias ProgressHandler = @Sendable (WhisperKitModelBootstrapProgress) -> Void

    public var modelsDirectory: URL
    public var repositoryID: String
    public var revision: String
    public var session: URLSession

    public init(
        sidecarsDirectory: URL,
        repositoryID: String = "argmaxinc/whisperkit-coreml",
        revision: String = "main",
        session: URLSession = .shared
    ) {
        self.modelsDirectory = sidecarsDirectory
            .appendingPathComponent("whisperkit", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        self.repositoryID = repositoryID
        self.revision = revision
        self.session = session
    }

    public func ensureRequiredBundledModels(progress: ProgressHandler? = nil) async throws -> [String] {
        try await ensureModels(WhisperKitModelInventory.requiredBundledModels, progress: progress)
    }

    @discardableResult
    public func ensureModels(_ models: [String], progress: ProgressHandler? = nil) async throws -> [String] {
        let unsupported = models.filter { !WhisperKitModelInventory.requiredBundledModels.contains($0) }
        if let first = unsupported.first { throw WhisperKitModelBootstrapError.invalidModel(first) }
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        var downloadedOrVerified: [String] = []
        for model in models {
            let destination = modelsDirectory.appendingPathComponent(model, isDirectory: true)
            if WhisperKitModelInventory.isModelUsable(destination) {
                progress?(WhisperKitModelBootstrapProgress(model: model, message: "模型已就绪：\(model)"))
                downloadedOrVerified.append(model)
                continue
            }
            progress?(WhisperKitModelBootstrapProgress(model: model, message: "开始准备模型：\(model)"))
            let files = try await listModelFiles(model)
            let totalBytes = files.reduce(Int64(0)) { $0 + Int64($1.size ?? 0) }
            var completedBytes: Int64 = 0
            for file in files {
                let relativePath = String(file.path.dropFirst(model.count + 1))
                let target = destination.appendingPathComponent(relativePath)
                let expectedSize = Int64(file.size ?? 0)
                let fileBaseCompletedBytes = completedBytes
                try await downloadIfNeeded(remotePath: file.path, destination: target, expectedSize: expectedSize) { fileCompleted in
                    progress?(WhisperKitModelBootstrapProgress(
                        model: model,
                        filePath: relativePath,
                        completedBytes: fileBaseCompletedBytes + fileCompleted,
                        totalBytes: totalBytes,
                        message: "正在下载 \(model)：\(relativePath)"
                    ))
                }
                completedBytes += expectedSize
            }
            let missing = requiredEntriesMissing(in: destination)
            if !missing.isEmpty { throw WhisperKitModelBootstrapError.incompleteModel(model, missing: missing) }
            progress?(WhisperKitModelBootstrapProgress(model: model, completedBytes: totalBytes, totalBytes: totalBytes, message: "模型已完成：\(model)"))
            downloadedOrVerified.append(model)
        }
        return downloadedOrVerified
    }

    public func requiredEntriesMissing(in modelDirectory: URL) -> [String] {
        let requiredEntries = [
            "AudioEncoder.mlmodelc",
            "MelSpectrogram.mlmodelc",
            "TextDecoder.mlmodelc",
            "config.json",
            "generation_config.json"
        ]
        return requiredEntries.filter { !FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent($0).path) }
    }

    private func listModelFiles(_ model: String) async throws -> [HuggingFaceTreeItem] {
        let url = URL(string: "https://huggingface.co/api/models/\(repositoryID)/tree/\(revision)/\(model)?recursive=true&expand=true")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WhisperKitModelBootstrapError.invalidAPIResponse("Unable to list \(model)")
        }
        let items = try JSONDecoder().decode([HuggingFaceTreeItem].self, from: data)
        let files = items.filter { $0.type == "file" }.sorted { $0.path < $1.path }
        guard !files.isEmpty else { throw WhisperKitModelBootstrapError.invalidAPIResponse("No files returned for \(model)") }
        return files
    }

    private func downloadIfNeeded(
        remotePath: String,
        destination: URL,
        expectedSize: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        if expectedSize > 0,
           let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           Int64(size) == expectedSize {
            progress(expectedSize)
            return
        }

        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = destination.appendingPathExtension("partial")
        var existingBytes: Int64 = 0
        if let size = try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            existingBytes = Int64(size)
            if expectedSize > 0, existingBytes > expectedSize {
                try? FileManager.default.removeItem(at: partial)
                existingBytes = 0
            }
        }
        if expectedSize > 0, existingBytes == expectedSize {
            try replaceItemAtomically(from: partial, to: destination)
            progress(expectedSize)
            return
        }

        var request = URLRequest(url: resolveURL(for: remotePath))
        if existingBytes > 0 {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WhisperKitModelBootstrapError.downloadFailed(remotePath)
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
                progress(written)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
            progress(written)
        }
        if expectedSize > 0, written != expectedSize {
            throw WhisperKitModelBootstrapError.downloadFailed("\(remotePath) expected \(expectedSize) bytes, got \(written)")
        }
        try handle.close()
        try replaceItemAtomically(from: partial, to: destination)
        progress(expectedSize > 0 ? expectedSize : written)
    }

    private func resolveURL(for remotePath: String) -> URL {
        URL(string: "https://huggingface.co/\(repositoryID)/resolve/\(revision)/\(remotePath)?download=true")!
    }

    private func replaceItemAtomically(from partial: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: partial, to: destination)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDestination = destination
        try? mutableDestination.setResourceValues(values)
    }
}

private struct HuggingFaceTreeItem: Decodable, Sendable {
    var type: String
    var path: String
    var size: Int?
}
