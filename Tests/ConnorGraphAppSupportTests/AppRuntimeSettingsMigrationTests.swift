import Foundation
import Testing
@testable import ConnorGraphAppSupport

struct AppRuntimeSettingsMigrationTests {
    private func makeRepository() throws -> (AppRuntimeSettingsRepository, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-settings-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (AppRuntimeSettingsRepository(configDirectory: directory), directory)
    }

    @Test
    func migratesLegacyDefaultRunDurationFromThirtyMinutesToOneHour() throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        // 模拟旧版本（schemaVersion 9、单轮上限 1800 秒）落盘的设置文件。
        let legacyJSON = """
        {
          "schemaVersion": 9,
          "loop": {
            "maxToolIterations": 256,
            "maxRunDurationSeconds": 1800,
            "maxConsecutiveToolResultErrors": 3,
            "toolTimeoutSeconds": 300,
            "stopAfterTurnWhenBudgetExceeded": false,
            "budget": {
              "maxTotalTokens": 80000,
              "reservationTokens": 8000,
              "hardLimitVetoMaxTokens": 120000,
              "hardLimitMaxTokens": 1000000
            },
            "promptMaxEstimatedTokens": 64000,
            "preflightMode": "contextual",
            "toolExposureMode": "contextual"
          }
        }
        """
        try legacyJSON.data(using: .utf8)!.write(to: repository.fileURL)

        let loaded = try repository.loadOrCreateDefault()
        #expect(loaded.schemaVersion == 10)
        #expect(loaded.loop.maxRunDurationSeconds == 3600)

        // 迁移结果落盘后再次加载，不应重复迁移或回退。
        let reloaded = try repository.loadOrCreateDefault()
        #expect(reloaded.schemaVersion == 10)
        #expect(reloaded.loop.maxRunDurationSeconds == 3600)
    }

    @Test
    func preservesNonDefaultRunDurationDuringMigration() throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        // 非默认值（7200 秒）随旧版本 schema 落盘：迁移应原样保留。
        let legacyJSON = """
        {
          "schemaVersion": 9,
          "loop": {
            "maxToolIterations": 256,
            "maxRunDurationSeconds": 7200,
            "maxConsecutiveToolResultErrors": 3,
            "toolTimeoutSeconds": 300,
            "stopAfterTurnWhenBudgetExceeded": false,
            "budget": {
              "maxTotalTokens": 80000,
              "reservationTokens": 8000,
              "hardLimitVetoMaxTokens": 120000,
              "hardLimitMaxTokens": 1000000
            },
            "promptMaxEstimatedTokens": 64000,
            "preflightMode": "contextual",
            "toolExposureMode": "contextual"
          }
        }
        """
        try legacyJSON.data(using: .utf8)!.write(to: repository.fileURL)

        let loaded = try repository.loadOrCreateDefault()
        #expect(loaded.schemaVersion == 10)
        #expect(loaded.loop.maxRunDurationSeconds == 7200)
    }

    @Test
    func freshDefaultsUseOneHourRunDuration() throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        let settings = try repository.loadOrCreateDefault()
        #expect(settings.schemaVersion == 10)
        #expect(settings.loop.maxRunDurationSeconds == 3600)
    }
}
