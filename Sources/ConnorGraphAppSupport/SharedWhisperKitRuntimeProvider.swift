import Foundation
import ConnorGraphCore

public protocol WhisperKitRuntimeProviding: Sendable {
    func healthCheck() async -> MediaRuntimeHealthReport
    func ensureBaselineModels(progress: WhisperKitModelBootstrapService.ProgressHandler?) async throws
    func preferredModel(for policy: SpeechInputModelPolicy) async -> String?
    func runtimeSnapshot(for policy: SpeechInputModelPolicy) async -> SpeechInputRuntimeSnapshot
}

public struct SharedWhisperKitRuntimeProvider: WhisperKitRuntimeProviding, Sendable {
    public var sidecarsDirectory: URL
    public var bundledRuntimeDirectory: URL?

    public init(
        sidecarsDirectory: URL,
        bundledRuntimeDirectory: URL? = MediaRuntimeSupervisor.defaultBundledRuntimeDirectory()
    ) {
        self.sidecarsDirectory = sidecarsDirectory
        self.bundledRuntimeDirectory = bundledRuntimeDirectory
    }

    public func healthCheck() async -> MediaRuntimeHealthReport {
        await MediaRuntimeSupervisor(
            sidecarsDirectory: sidecarsDirectory,
            bundledRuntimeDirectory: bundledRuntimeDirectory
        ).healthCheck()
    }

    public func ensureBaselineModels(progress: WhisperKitModelBootstrapService.ProgressHandler? = nil) async throws {
        let service = WhisperKitModelBootstrapService(sidecarsDirectory: sidecarsDirectory)
        _ = try await service.ensureRequiredBundledModels(progress: progress)
    }

    public func preferredModel(for policy: SpeechInputModelPolicy) async -> String? {
        let root = resolvedRuntimeRoot()
        return Self.preferredModel(for: policy, runtimeRoot: root)
    }

    public func runtimeSnapshot(for policy: SpeechInputModelPolicy) async -> SpeechInputRuntimeSnapshot {
        let root = resolvedRuntimeRoot()
        let selected = Self.preferredModel(for: policy, runtimeRoot: root)
        return SpeechInputRuntimeSnapshot(
            selectedModelID: selected,
            localRuntimeAvailable: selected != nil,
            fallbackReason: fallbackReason(for: policy, selectedModelID: selected, runtimeRoot: root),
            policy: policy
        )
    }

    public static func preferredModel(for policy: SpeechInputModelPolicy, runtimeRoot: URL) -> String? {
        let medium = WhisperKitModelInventory.defaultModel
        let small = WhisperKitModelInventory.fastModel
        let highAccuracy = WhisperKitModelInventory.optionalHighAccuracyModels.first {
            isReady($0, runtimeRoot: runtimeRoot)
        }
        let isMediumReady = isReady(medium, runtimeRoot: runtimeRoot)
        let isSmallReady = isReady(small, runtimeRoot: runtimeRoot)

        switch policy {
        case .appleSpeechOnly:
            return nil
        case .automaticRecommended, .balanced:
            if isMediumReady { return medium }
            if isSmallReady { return small }
            return nil
        case .speedFirst:
            if isSmallReady { return small }
            if isMediumReady { return medium }
            return nil
        case .highAccuracy:
            if let highAccuracy { return highAccuracy }
            if isMediumReady { return medium }
            if isSmallReady { return small }
            return nil
        }
    }

    private static func isReady(_ modelID: String, runtimeRoot: URL) -> Bool {
        WhisperKitModelInventory.isModelUsable(
            runtimeRoot
                .appendingPathComponent("whisperkit", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent(modelID, isDirectory: true)
        )
    }

    private func resolvedRuntimeRoot() -> URL {
        if let bundledRuntimeDirectory,
           WhisperKitModelInventory.missingRequiredModels(in: bundledRuntimeDirectory).isEmpty {
            return bundledRuntimeDirectory
        }
        return sidecarsDirectory
    }

    private func fallbackReason(for policy: SpeechInputModelPolicy, selectedModelID: String?, runtimeRoot: URL) -> String? {
        guard policy != .appleSpeechOnly else { return "系统语音识别模式，不使用本地 WhisperKit 模型。" }
        guard let selectedModelID else { return "本地 WhisperKit baseline 尚未准备完成。" }
        if selectedModelID == WhisperKitModelInventory.fastModel, policy != .speedFirst {
            return "Medium 尚未就绪，当前使用 Small fallback。"
        }
        if policy == .highAccuracy && !WhisperKitModelInventory.optionalHighAccuracyModels.contains(selectedModelID) {
            return "高准确率模型尚未安装，当前使用 baseline 模型。"
        }
        return nil
    }
}
