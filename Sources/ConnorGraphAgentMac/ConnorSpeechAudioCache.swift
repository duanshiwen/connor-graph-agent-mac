import AVFoundation
import CryptoKit
import Foundation

@MainActor
final class ConnorSpeechAudioCache {
    typealias Compressor = @Sendable (_ sourceWAV: URL, _ destinationM4A: URL) async throws -> Void

    private let directory: URL?
    private let fileManager: FileManager
    private let compressor: Compressor

    init(
        directory: URL?,
        fileManager: FileManager = .default,
        compressor: Compressor? = nil
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.compressor = compressor ?? Self.compressWAVToM4A
    }

    func cachedURL(for key: String) -> URL? {
        guard let directory else { return nil }
        let baseName = cacheFileName(for: key)
        for pathExtension in ["m4a", "wav"] {
            let candidate = directory.appendingPathComponent(baseName).appendingPathExtension(pathExtension)
            if fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    func store(wavData: Data, for key: String) async throws -> URL {
        guard let directory else {
            let temporaryURL = fileManager.temporaryDirectory
                .appendingPathComponent("connor-mimo-speech-\(UUID().uuidString)")
                .appendingPathExtension("wav")
            try wavData.write(to: temporaryURL, options: .atomic)
            return temporaryURL
        }
        if let cached = cachedURL(for: key) { return cached }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let baseName = cacheFileName(for: key)
        let sourceURL = directory
            .appendingPathComponent(".\(baseName)-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let temporaryM4AURL = directory
            .appendingPathComponent(".\(baseName)-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        defer {
            try? fileManager.removeItem(at: sourceURL)
            try? fileManager.removeItem(at: temporaryM4AURL)
        }
        try wavData.write(to: sourceURL, options: .atomic)

        let finalM4AURL = directory.appendingPathComponent(baseName).appendingPathExtension("m4a")
        do {
            try await compressor(sourceURL, temporaryM4AURL)
            try fileManager.moveItem(at: temporaryM4AURL, to: finalM4AURL)
            return finalM4AURL
        } catch {
            let finalWAVURL = directory.appendingPathComponent(baseName).appendingPathExtension("wav")
            try wavData.write(to: finalWAVURL, options: .atomic)
            return finalWAVURL
        }
    }

    private func cacheFileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func compressWAVToM4A(sourceURL: URL, destinationURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ConnorSpeechAudioCacheError.compressionUnavailable
        }
        exporter.outputURL = destinationURL
        exporter.outputFileType = .m4a
        await exporter.export()
        guard exporter.status == .completed else {
            throw exporter.error ?? ConnorSpeechAudioCacheError.compressionFailed
        }
    }
}

enum ConnorSpeechAudioCacheError: Error {
    case compressionUnavailable
    case compressionFailed
}
