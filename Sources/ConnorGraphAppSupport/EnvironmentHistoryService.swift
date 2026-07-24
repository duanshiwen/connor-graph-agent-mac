import Foundation

public enum EnvironmentHistoryCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case weather
    case airQuality = "air_quality"
}

public struct EnvironmentHistoryResult: Sendable, Equatable {
    public var regions: [StoredEnvironmentRegion]
    public var startDate: Date
    public var endDate: Date
    public var weather: [EnvironmentWeatherPoint]
    public var airQuality: [EnvironmentAirQualityPoint]
}

public actor EnvironmentHistoryService {
    private let storeTask: Task<SQLiteEnvironmentStore, Error>

    public init(databaseURL: URL) {
        storeTask = Task { try await SQLiteEnvironmentStore.open(databaseURL: databaseURL) }
    }

    public func query(
        placeName: String,
        startDate: Date,
        endDate: Date,
        categories: Set<EnvironmentHistoryCategory>
    ) async throws -> EnvironmentHistoryResult? {
        guard startDate <= endDate, !categories.isEmpty else { return nil }
        let store = try await storeTask.value
        let regions = try await store.regions(matching: placeName)
        guard !regions.isEmpty else { return nil }
        var weather: [EnvironmentWeatherPoint] = []
        var airQuality: [EnvironmentAirQualityPoint] = []
        for region in regions {
            if categories.contains(.weather) {
                weather += try await store.weatherPoints(regionID: region.id, from: startDate, through: endDate)
            }
            if categories.contains(.airQuality) {
                airQuality += try await store.airQualityPoints(regionID: region.id, from: startDate, through: endDate)
            }
        }
        return EnvironmentHistoryResult(
            regions: regions,
            startDate: startDate,
            endDate: endDate,
            weather: weather.sorted { $0.observedAt < $1.observedAt },
            airQuality: airQuality.sorted { $0.observedAt < $1.observedAt }
        )
    }
}
