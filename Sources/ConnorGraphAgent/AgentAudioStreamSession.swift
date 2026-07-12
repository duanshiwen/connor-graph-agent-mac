import Foundation

public enum AgentAudioStreamSessionError: Error, Sendable, Equatable {
    case invalidFormat
    case outOfOrder(expected: Int, actual: Int)
    case bufferLimitExceeded(Int)
    case totalByteLimitExceeded(Int64)
    case incompleteSampleFrame
    case notStarted
}

public struct AgentAudioStreamConfiguration: Sendable, Equatable {
    public var startupBufferBytes: Int
    public var lowWatermarkBytes: Int
    public var highWatermarkBytes: Int
    public var maximumBufferedBytes: Int
    public var maximumTotalBytes: Int64

    public init(startupBufferBytes: Int = 9_600, lowWatermarkBytes: Int = 4_800, highWatermarkBytes: Int = 48_000, maximumBufferedBytes: Int = 96_000, maximumTotalBytes: Int64 = 50_000_000) {
        self.startupBufferBytes = startupBufferBytes
        self.lowWatermarkBytes = lowWatermarkBytes
        self.highWatermarkBytes = highWatermarkBytes
        self.maximumBufferedBytes = maximumBufferedBytes
        self.maximumTotalBytes = maximumTotalBytes
    }
}

public struct AgentAudioStreamSnapshot: Sendable, Equatable {
    public var bufferedBytes: Int
    public var totalBytes: Int64
    public var isReadyForPlayback: Bool
    public var shouldApplyBackpressure: Bool
    public var underrunCount: Int
}

public actor AgentAudioStreamSession {
    public let id: String
    public let configuration: AgentAudioStreamConfiguration
    private var format: AgentGeneratedAudioFormat?
    private var expectedSequence = 0
    private var pendingPartialFrame = Data()
    private var queuedFrames: [Data] = []
    private var bufferedBytes = 0
    private var totalBytes: Int64 = 0
    private var underrunCount = 0
    private var rawPCMURL: URL?
    private var rawHandle: FileHandle?

    public init(id: String = UUID().uuidString, configuration: AgentAudioStreamConfiguration = AgentAudioStreamConfiguration()) {
        self.id = id
        self.configuration = configuration
    }

    public func start(format: AgentGeneratedAudioFormat, temporaryDirectory: URL = FileManager.default.temporaryDirectory) throws {
        guard format.encoding == "pcm_s16le", format.sampleRate > 0, format.channelCount > 0, format.bitsPerChannel == 16 else {
            throw AgentAudioStreamSessionError.invalidFormat
        }
        self.format = format
        let url = temporaryDirectory.appendingPathComponent("connor-audio-stream-\(id).pcm")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        rawPCMURL = url
        rawHandle = try FileHandle(forWritingTo: url)
    }

    public func append(sequence: Int, data: Data) throws -> [Data] {
        guard let format else { throw AgentAudioStreamSessionError.notStarted }
        guard sequence == expectedSequence else { throw AgentAudioStreamSessionError.outOfOrder(expected: expectedSequence, actual: sequence) }
        expectedSequence += 1
        guard totalBytes + Int64(data.count) <= configuration.maximumTotalBytes else { throw AgentAudioStreamSessionError.totalByteLimitExceeded(configuration.maximumTotalBytes) }
        try rawHandle?.write(contentsOf: data)
        totalBytes += Int64(data.count)

        var combined = pendingPartialFrame
        combined.append(data)
        let bytesPerFrame = format.channelCount * (format.bitsPerChannel / 8)
        let completeCount = combined.count - combined.count % bytesPerFrame
        pendingPartialFrame = completeCount < combined.count ? combined.subdata(in: completeCount..<combined.count) : Data()
        guard completeCount > 0 else { return [] }
        let framed = combined.subdata(in: 0..<completeCount)
        guard bufferedBytes + framed.count <= configuration.maximumBufferedBytes else { throw AgentAudioStreamSessionError.bufferLimitExceeded(configuration.maximumBufferedBytes) }
        queuedFrames.append(framed)
        bufferedBytes += framed.count
        return [framed]
    }

    public func consumeNextFrame() -> Data? {
        guard !queuedFrames.isEmpty else {
            underrunCount += 1
            return nil
        }
        let frame = queuedFrames.removeFirst()
        bufferedBytes -= frame.count
        return frame
    }

    public func snapshot() -> AgentAudioStreamSnapshot {
        AgentAudioStreamSnapshot(
            bufferedBytes: bufferedBytes,
            totalBytes: totalBytes,
            isReadyForPlayback: bufferedBytes >= configuration.startupBufferBytes,
            shouldApplyBackpressure: bufferedBytes >= configuration.highWatermarkBytes,
            underrunCount: underrunCount
        )
    }

    public func finish(outputDirectory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        guard let format, let rawPCMURL else { throw AgentAudioStreamSessionError.notStarted }
        guard pendingPartialFrame.isEmpty else { throw AgentAudioStreamSessionError.incompleteSampleFrame }
        try rawHandle?.close()
        rawHandle = nil
        let pcm = try Data(contentsOf: rawPCMURL)
        let wavURL = outputDirectory.appendingPathComponent("connor-audio-stream-\(id).wav")
        try Self.wavData(pcm: pcm, format: format).write(to: wavURL, options: [.atomic])
        try? FileManager.default.removeItem(at: rawPCMURL)
        self.rawPCMURL = nil
        return wavURL
    }

    public func cancel() {
        try? rawHandle?.close()
        rawHandle = nil
        if let rawPCMURL { try? FileManager.default.removeItem(at: rawPCMURL) }
        rawPCMURL = nil
        queuedFrames.removeAll()
        bufferedBytes = 0
        pendingPartialFrame.removeAll()
    }

    public static func wavData(pcm: Data, format: AgentGeneratedAudioFormat) -> Data {
        let channels = UInt16(format.channelCount)
        let sampleRate = UInt32(format.sampleRate)
        let bits = UInt16(format.bitsPerChannel)
        let blockAlign = channels * bits / 8
        let byteRate = sampleRate * UInt32(blockAlign)
        var data = Data()
        func ascii(_ value: String) { data.append(Data(value.utf8)) }
        func u16(_ value: UInt16) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        ascii("RIFF"); u32(UInt32(36 + pcm.count)); ascii("WAVEfmt "); u32(16); u16(1); u16(channels)
        u32(sampleRate); u32(byteRate); u16(blockAlign); u16(bits); ascii("data"); u32(UInt32(pcm.count)); data.append(pcm)
        return data
    }
}
