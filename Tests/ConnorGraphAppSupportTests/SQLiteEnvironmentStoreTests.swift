import Foundation
import Testing
import ConnorGraphAgent
@testable import ConnorGraphAppSupport

@Test func coarseEnvironmentGridIsStableAndDoesNotRetainInputCoordinate() throws {
    let first = try #require(AgentEnvironmentRegion.containing(latitude: 30.12345, longitude: 120.98765))
    let nearby = try #require(AgentEnvironmentRegion.containing(latitude: 30.124, longitude: 120.986))

    #expect(first == nearby)
    #expect(first.gridCellID == "v1:2402:6019")
    #expect(first.centerLatitude != 30.12345)
    #expect(first.centerLongitude != 120.98765)
}

@Test func environmentStoreCreatesSchemaAndUpsertsPermanentWeatherPoints() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    let store = try await SQLiteEnvironmentStore.open(databaseURL: paths.environmentDatabaseURL)
    let region = try #require(AgentEnvironmentRegion.containing(latitude: 30.12345, longitude: 120.98765))
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let regionID = try await store.upsertRegion(
        region,
        timeZoneIdentifier: "Asia/Shanghai",
        administrativeArea: "Zhejiang",
        locality: "Hangzhou",
        now: now
    )
    let original = EnvironmentWeatherPoint(
        regionID: regionID,
        observedAt: now,
        dataKind: .currentObservation,
        provider: "Open-Meteo",
        temperatureCelsius: 30,
        fetchedAt: now
    )
    try await store.upsertWeatherPoint(original)
    var corrected = original
    corrected.temperatureCelsius = 31
    try await store.upsertWeatherPoint(corrected)

    let storedRegion = try #require(try await store.region(gridCellID: region.gridCellID))
    let points = try await store.weatherPoints(regionID: regionID, from: now.addingTimeInterval(-1), through: now.addingTimeInterval(1))

    #expect(storedRegion.centerLatitude == region.centerLatitude)
    #expect(storedRegion.centerLongitude == region.centerLongitude)
    #expect(points.count == 1)
    #expect(points.first?.temperatureCelsius == 31)
    #expect(FileManager.default.fileExists(atPath: paths.environmentDatabaseURL.path))
}
