import AVFoundation
import Foundation
import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Connor speech audio cache tests")
struct ConnorSpeechAudioCacheTests {
    @Test func compressedAudioPersistsAcrossCacheInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-speech-cache-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ConnorSpeechAudioCache(directory: directory) { _, destination in
            try Data("compressed".utf8).write(to: destination)
        }

        let storedURL = try await cache.store(wavData: Data("wav".utf8), for: "message:1:female")

        #expect(storedURL.pathExtension == "m4a")
        #expect(try Data(contentsOf: storedURL) == Data("compressed".utf8))
        let reloadedCache = ConnorSpeechAudioCache(directory: directory)
        #expect(reloadedCache.cachedURL(for: "message:1:female") == storedURL)
    }

    @Test func originalWAVIsCachedWhenCompressionFails() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-speech-cache-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = Data("wav-data".utf8)
        let cache = ConnorSpeechAudioCache(directory: directory) { _, _ in
            throw ConnorSpeechAudioCacheError.compressionFailed
        }

        let storedURL = try await cache.store(wavData: expected, for: "message:2:male")

        #expect(storedURL.pathExtension == "wav")
        #expect(try Data(contentsOf: storedURL) == expected)
        #expect(cache.cachedURL(for: "message:2:male") == storedURL)
    }

    @Test func builtInEncoderProducesReadableM4A() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-speech-cache-tests-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = root.appendingPathComponent("source.wav")
        let cacheDirectory = root.appendingPathComponent("cache", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
            buffer.frameLength = 16_000
            let sourceFile = try AVAudioFile(forWriting: sourceURL, settings: format.settings)
            try sourceFile.write(from: buffer)
        }

        let storedURL = try await ConnorSpeechAudioCache(directory: cacheDirectory)
            .store(wavData: Data(contentsOf: sourceURL), for: "real-encoder")

        #expect(storedURL.pathExtension == "m4a")
        let compressedFile = try AVAudioFile(forReading: storedURL)
        #expect(compressedFile.length > 0)
    }
}
