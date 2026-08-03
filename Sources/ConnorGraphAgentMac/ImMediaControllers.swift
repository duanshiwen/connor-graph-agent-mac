import AppKit
import AVFoundation
import Foundation
import Observation
import UniformTypeIdentifiers
import ConnorGraphCore

enum ImMediaInspector {
    static func metadata(for url: URL, type: ImMessageType, duration: Int? = nil) async -> ImMediaMetadata {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        var width: Int?
        var height: Int?
        var resolvedDuration = duration

        if type == .image, let image = NSImage(contentsOf: url) {
            var rect = CGRect(origin: .zero, size: image.size)
            if let representation = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                width = representation.width
                height = representation.height
            }
        } else if type == .video {
            let asset = AVURLAsset(url: url)
            if let value = try? await asset.load(.duration), value.isNumeric {
                resolvedDuration = Int(ceil(value.seconds))
            }
            if let tracks = try? await asset.loadTracks(withMediaType: .video),
               let track = tracks.first,
               let size = try? await track.load(.naturalSize) {
                width = Int(abs(size.width))
                height = Int(abs(size.height))
            }
        }

        return ImMediaMetadata(
            width: width,
            height: height,
            duration: resolvedDuration,
            fileSize: values?.fileSize.map(Int64.init),
            fileName: url.lastPathComponent,
            mimeType: values?.contentType?.preferredMIMEType,
            attachmentKind: type == .file ? "file" : nil
        )
    }
}

@MainActor
@Observable
final class ImVoiceRecorder: NSObject, AVAudioRecorderDelegate {
    static let maximumDuration = 60

    private(set) var isRecording = false
    private(set) var elapsedSeconds = 0
    private(set) var finishedRecording: (url: URL, duration: Int)?

    private var recorder: AVAudioRecorder?
    private var timerTask: Task<Void, Never>?

    func start() async throws {
        guard !isRecording else { return }
        guard await Self.requestPermission() else { throw ImVoiceRecorderError.permissionDenied }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-im-voice-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.prepareToRecord()
        guard recorder.record(forDuration: TimeInterval(Self.maximumDuration)) else {
            throw ImVoiceRecorderError.cannotStart
        }
        self.recorder = recorder
        finishedRecording = nil
        elapsedSeconds = 0
        isRecording = true
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isRecording else { return }
                self.elapsedSeconds = min(Self.maximumDuration, Int(self.recorder?.currentTime ?? 0))
                if self.elapsedSeconds >= Self.maximumDuration {
                    _ = self.stop()
                }
            }
        }
    }

    func stop() -> (url: URL, duration: Int)? {
        guard let recorder else { return nil }
        let duration = max(1, min(Self.maximumDuration, Int(ceil(recorder.currentTime))))
        recorder.stop()
        timerTask?.cancel()
        timerTask = nil
        self.recorder = nil
        isRecording = false
        elapsedSeconds = 0
        return (recorder.url, duration)
    }

    func takeFinishedRecording() -> (url: URL, duration: Int)? {
        defer { finishedRecording = nil }
        return finishedRecording
    }

    func cancel() {
        let url = recorder?.url
        recorder?.stop()
        timerTask?.cancel()
        timerTask = nil
        recorder = nil
        isRecording = false
        elapsedSeconds = 0
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.timerTask?.cancel()
            self.timerTask = nil
            if flag {
                self.finishedRecording = (recorder.url, Self.maximumDuration)
            }
            self.recorder = nil
            self.isRecording = false
            self.elapsedSeconds = 0
        }
    }

    private static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }
}

enum ImVoiceRecorderError: LocalizedError {
    case permissionDenied
    case cannotStart

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "没有麦克风权限"
        case .cannotStart: return "无法开始录音"
        }
    }
}

@MainActor
@Observable
final class ImMediaPlaybackController {
    private(set) var playingMessageID: String?
    private var player: AVPlayer?
    private var completionObserver: NSObjectProtocol?

    func toggle(messageID: String, url: URL) {
        if playingMessageID == messageID {
            stop()
            return
        }
        stop()
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        playingMessageID = messageID
        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
        }
        player?.play()
    }

    func stop() {
        player?.pause()
        player = nil
        playingMessageID = nil
        if let completionObserver {
            NotificationCenter.default.removeObserver(completionObserver)
            self.completionObserver = nil
        }
    }
}
