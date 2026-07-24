import Foundation
import Testing
import ConnorGraphAgent
@testable import ConnorGraphAppSupport

@Test func snapshotPersistenceStoresOnlyGridCoordinatesAndForecasts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    let persistence = EnvironmentSnapshotPersistence(databaseURL: paths.environmentDatabaseURL)
    let region = try #require(AgentEnvironmentRegion.containing(latitude: 30.12345, longitude: 120.98765))
    let capturedAt = Date(timeIntervalSince1970: 1_790_000_000)
    let snapshot = AgentEnvironmentSnapshot(
        capturedAt: capturedAt,
        location: AgentEnvironmentLocation(
            status: .available,
            locality: "Hangzhou",
            administrativeArea: "Zhejiang",
            country: "China",
            gridCellID: region.gridCellID,
            latitude: region.centerLatitude,
            longitude: region.centerLongitude,
            capturedAt: capturedAt
        ),
        localTime: AgentEnvironmentLocalTime(
            timeZoneIdentifier: "Asia/Shanghai",
            localDateTime: "2026-09-22 09:00:00",
            dayPeriod: "morning"
        ),
        weather: AgentEnvironmentWeather(
            status: .available,
            temperatureCelsius: 25,
            hourlyForecast: [
                AgentEnvironmentHourlyWeather(localTime: "2026-09-22T10:00", temperatureCelsius: 26)
            ],
            source: "Open-Meteo",
            sourceURL: "https://open-meteo.com/",
            updatedAt: capturedAt
        )
    )

    await persistence.record(snapshot)

    let store = try await SQLiteEnvironmentStore.open(databaseURL: paths.environmentDatabaseURL)
    let storedRegion = try #require(try await store.region(gridCellID: region.gridCellID))
    let points = try await store.weatherPoints(
        regionID: storedRegion.id,
        from: capturedAt.addingTimeInterval(-1),
        through: capturedAt.addingTimeInterval(24 * 60 * 60)
    )
    #expect(storedRegion.centerLatitude == region.centerLatitude)
    #expect(storedRegion.centerLongitude == region.centerLongitude)
    #expect(points.map(\.dataKind).contains(.currentObservation))
    #expect(points.map(\.dataKind).contains(.forecast))

    let databaseBytes = try Data(contentsOf: paths.environmentDatabaseURL)
    let databaseText = String(decoding: databaseBytes, as: UTF8.self)
    #expect(!databaseText.contains("30.12345"))
    #expect(!databaseText.contains("120.98765"))
}
