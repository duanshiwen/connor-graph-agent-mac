import AVFoundation
import Foundation
import os
import ConnorGraphAgent
import ConnorGraphAppSupport

/// Serial audio data plane. PCM allocation, copying, and node scheduling must never
/// inherit MainActor isolation from the SwiftUI playback controller.
actor AgentPCMStreamPlaybackEngine {
    private static let signposter = OSSignposter(
        subsystem: AppPerformanceLog.subsystem,
        category: "AudioPerformance"
    )

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private(set) var isStarted = false
    private var lastScheduleTimestamp: UInt64?

    init() {
        engine.attach(playerNode)
    }

    func start(format generatedFormat: AgentGeneratedAudioFormat) throws {
        stop()
        guard generatedFormat.encoding == "pcm_s16le",
              let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: generatedFormat.sampleRate,
                channels: AVAudioChannelCount(generatedFormat.channelCount),
                interleaved: true
              ) else { throw AgentAudioStreamSessionError.invalidFormat }
        self.format = format
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        try engine.start()
        playerNode.play()
        isStarted = true
    }

    func schedule(frame data: Data) throws {
        let interval = Self.signposter.beginInterval("Audio.FrameArrivalToSchedule")
        defer { Self.signposter.endInterval("Audio.FrameArrivalToSchedule", interval) }
        guard let format else { throw AgentAudioStreamSessionError.notStarted }
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0, data.count % bytesPerFrame == 0 else { throw AgentAudioStreamSessionError.incompleteSampleFrame }
        let frameCount = AVAudioFrameCount(data.count / bytesPerFrame)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { throw AgentAudioStreamSessionError.invalidFormat }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { source in
            guard let sourceBase = source.baseAddress,
                  let destination = buffer.mutableAudioBufferList.pointee.mBuffers.mData else { return }
            memcpy(destination, sourceBase, data.count)
            buffer.mutableAudioBufferList.pointee.mBuffers.mDataByteSize = UInt32(data.count)
        }
        playerNode.scheduleBuffer(buffer)

        let now = DispatchTime.now().uptimeNanoseconds
        if let previous = lastScheduleTimestamp {
            let gapMilliseconds = Double(now - previous) / 1_000_000
            if gapMilliseconds >= 100 {
                Self.signposter.emitEvent("Audio.ScheduleGap", "duration_ms=\(gapMilliseconds)")
            }
        }
        lastScheduleTimestamp = now
    }

    func pause() { playerNode.pause() }
    func resume() { if !playerNode.isPlaying { playerNode.play() } }

    func stop() {
        playerNode.stop()
        engine.stop()
        engine.disconnectNodeOutput(playerNode)
        format = nil
        isStarted = false
        lastScheduleTimestamp = nil
    }
}
