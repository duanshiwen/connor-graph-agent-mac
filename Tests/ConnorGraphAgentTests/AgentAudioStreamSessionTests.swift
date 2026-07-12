import Foundation
import Testing
@testable import ConnorGraphAgent

@Suite("Agent Audio Stream Session Tests")
struct AgentAudioStreamSessionTests {
    let format = AgentGeneratedAudioFormat(encoding: "pcm_s16le", sampleRate: 24_000, channelCount: 1, bitsPerChannel: 16)

    @Test func arbitraryByteBoundariesAreReframedIntoCompleteSamples() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = AgentAudioStreamSession(configuration: AgentAudioStreamConfiguration(startupBufferBytes: 4, maximumBufferedBytes: 32))
        try await session.start(format: format, temporaryDirectory: root)
        #expect(try await session.append(sequence: 0, data: Data([1])).isEmpty)
        let framed = try await session.append(sequence: 1, data: Data([2, 3, 4]))
        #expect(framed == [Data([1, 2, 3, 4])])
        #expect(await session.snapshot().isReadyForPlayback)
        #expect(await session.consumeNextFrame() == Data([1, 2, 3, 4]))
        let wav = try await session.finish(outputDirectory: root)
        let data = try Data(contentsOf: wav)
        #expect(String(data: data.prefix(4), encoding: .ascii) == "RIFF")
        #expect(String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WAVE")
        #expect(data.suffix(4) == Data([1, 2, 3, 4]))
    }

    @Test func rejectsOutOfOrderAndBufferOverflow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = AgentAudioStreamSession(configuration: AgentAudioStreamConfiguration(maximumBufferedBytes: 4))
        try await session.start(format: format, temporaryDirectory: root)
        await #expect(throws: AgentAudioStreamSessionError.outOfOrder(expected: 0, actual: 1)) {
            try await session.append(sequence: 1, data: Data([0, 0]))
        }
        _ = try await session.append(sequence: 0, data: Data([0, 0, 0, 0]))
        await #expect(throws: AgentAudioStreamSessionError.bufferLimitExceeded(4)) {
            try await session.append(sequence: 1, data: Data([0, 0]))
        }
        await session.cancel()
    }

    @Test func incompleteFinalSampleFailsAndEmptyConsumeCountsUnderrun() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = AgentAudioStreamSession()
        try await session.start(format: format, temporaryDirectory: root)
        #expect(await session.consumeNextFrame() == nil)
        _ = try await session.append(sequence: 0, data: Data([1]))
        await #expect(throws: AgentAudioStreamSessionError.incompleteSampleFrame) {
            try await session.finish(outputDirectory: root)
        }
        #expect(await session.snapshot().underrunCount == 1)
        await session.cancel()
    }
}
