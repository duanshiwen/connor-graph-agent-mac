import AVFoundation
import Foundation
import ConnorGraphAgent

@MainActor
final class AgentPCMStreamPlaybackEngine {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private(set) var isStarted = false

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
    }

    func pause() { playerNode.pause() }
    func resume() { if !playerNode.isPlaying { playerNode.play() } }

    func stop() {
        playerNode.stop()
        engine.stop()
        engine.disconnectNodeOutput(playerNode)
        format = nil
        isStarted = false
    }
}
