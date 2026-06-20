import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Shared WhisperKit Runtime Provider Tests")
struct SharedWhisperKitRuntimeProviderTests {
    @Test func automaticRecommendedUsesMediumWhenBaselineReady() throws {
        let root = try makeRuntimeRoot(models: [
            WhisperKitModelInventory.fastModel,
            WhisperKitModelInventory.defaultModel
        ])

        let selected = SharedWhisperKitRuntimeProvider.preferredModel(
            for: .automaticRecommended,
            runtimeRoot: root
        )

        #expect(selected == WhisperKitModelInventory.defaultModel)
    }

    @Test func automaticRecommendedFallsBackToSmallWhenMediumMissing() throws {
        let root = try makeRuntimeRoot(models: [WhisperKitModelInventory.fastModel])

        let selected = SharedWhisperKitRuntimeProvider.preferredModel(
            for: .automaticRecommended,
            runtimeRoot: root
        )

        #expect(selected == WhisperKitModelInventory.fastModel)
    }

    @Test func speedFirstPrefersSmallEvenWhenMediumReady() throws {
        let root = try makeRuntimeRoot(models: [
            WhisperKitModelInventory.fastModel,
            WhisperKitModelInventory.defaultModel
        ])

        let selected = SharedWhisperKitRuntimeProvider.preferredModel(
            for: .speedFirst,
            runtimeRoot: root
        )

        #expect(selected == WhisperKitModelInventory.fastModel)
    }

    @Test func highAccuracyUsesOptionalModelWhenInstalled() throws {
        let highAccuracy = WhisperKitModelInventory.optionalHighAccuracyModels[0]
        let root = try makeRuntimeRoot(models: [
            WhisperKitModelInventory.fastModel,
            WhisperKitModelInventory.defaultModel,
            highAccuracy
        ])

        let selected = SharedWhisperKitRuntimeProvider.preferredModel(
            for: .highAccuracy,
            runtimeRoot: root
        )

        #expect(selected == highAccuracy)
    }

    @Test func appleSpeechOnlyReturnsNoLocalModel() throws {
        let root = try makeRuntimeRoot(models: [
            WhisperKitModelInventory.fastModel,
            WhisperKitModelInventory.defaultModel
        ])

        let selected = SharedWhisperKitRuntimeProvider.preferredModel(
            for: .appleSpeechOnly,
            runtimeRoot: root
        )

        #expect(selected == nil)
    }

    private func makeRuntimeRoot(models: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-whisperkit-runtime-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        for model in models {
            try createUsableWhisperKitModel(named: model, in: root)
        }
        return root
    }

    private func createUsableWhisperKitModel(named name: String, in runtimeRoot: URL) throws {
        let directory = runtimeRoot
            .appendingPathComponent("whisperkit", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for entry in [
            "AudioEncoder.mlmodelc",
            "MelSpectrogram.mlmodelc",
            "TextDecoder.mlmodelc"
        ] {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(entry, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        for entry in ["config.json", "generation_config.json"] {
            FileManager.default.createFile(
                atPath: directory.appendingPathComponent(entry).path,
                contents: Data("{}".utf8)
            )
        }
    }
}
