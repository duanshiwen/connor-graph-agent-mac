import Foundation
import ConnorGraphAgent

public struct EnvironmentHistoryResult: Sendable, Equatable {
    public var region: StoredEnvironmentRegion
    public var startDate: Date
    public var endDate: Date
    public var weather: [EnvironmentWeatherPoint]
    public var airQuality: [EnvironmentAirQualityPoint]
}

public actor EnvironmentHistoryService {
    private static let maximumRequestBatchDays = 30
    private let storeTask: Task<SQLiteEnvironmentStore, Error>
    private let provider: any EnvironmentHistoryProviding & EnvironmentRegionResolving
    private let now: @Sendable () -> Date

    public init(
        databaseURL: URL,
        provider: any EnvironmentHistoryProviding & EnvironmentRegionResolving = OpenMeteoEnvironmentHistoryProvider(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        storeTask = Task { try await SQLiteEnvironmentStore.open(databaseURL: databaseURL) }
        self.provider = provider
        self.now = now
    }

    public func query(
        placeName: String,
        startDate: Date,
        endDate: Date,
        categories: Set<EnvironmentHistoryCategory>,
        fillMissing: Bool
    ) async throws -> EnvironmentHistoryResult? {
        guard startDate <= endDate, !categories.isEmpty else { return nil }
        guard let resolved = try await provider.resolve(placeName: placeName) else { return nil }
        let store = try await storeTask.value
        let regionID = try await store.upsertRegion(
            resolved.region,
            timeZoneIdentifier: resolved.timeZoneIdentifier,
            countryCode: resolved.countryCode,
            administrativeArea: resolved.administrativeArea,
            locality: resolved.locality,
            now: now()
        )
        if fillMissing {
            try await fill(
                request: EnvironmentHistoryFetchRequest(region: resolved, startDate: startDate, endDate: endDate),
                regionID: regionID,
                categories: categories,
                store: store
            )
        }
        guard let storedRegion = try await store.region(gridCellID: resolved.region.gridCellID) else { return nil }
        let weather = categories.contains(.weather)
            ? try await store.weatherPoints(regionID: regionID, from: startDate, through: endDate)
            : []
        let airQuality = categories.contains(.airQuality)
            ? try await store.airQualityPoints(regionID: regionID, from: startDate, through: endDate)
            : []
        return EnvironmentHistoryResult(
            region: storedRegion,
            startDate: startDate,
            endDate: endDate,
            weather: weather,
            airQuality: airQuality
        )
    }

    private func fill(
        request: EnvironmentHistoryFetchRequest,
        regionID: Int64,
        categories: Set<EnvironmentHistoryCategory>,
        store: SQLiteEnvironmentStore
    ) async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: request.region.timeZoneIdentifier) ?? .gmt
        var chunkStart = request.startDate
        while chunkStart <= request.endDate {
            let proposedEnd = calendar.date(
                byAdding: .day,
                value: Self.maximumRequestBatchDays - 1,
                to: chunkStart
            ) ?? request.endDate
            let chunkEnd = min(proposedEnd, request.endDate)
            let chunk = EnvironmentHistoryFetchRequest(region: request.region, startDate: chunkStart, endDate: chunkEnd)
            if categories.contains(.weather) {
                let samples = try await provider.weather(for: chunk)
                for sample in samples {
                    try await store.upsertWeatherPoint(EnvironmentWeatherPoint(
                        regionID: regionID,
                        observedAt: sample.observedAt,
                        dataKind: .historicalReanalysis,
                        provider: "Open-Meteo Historical Weather",
                        temperatureCelsius: sample.temperatureCelsius,
                        apparentTemperatureCelsius: sample.apparentTemperatureCelsius,
                        relativeHumidityPercent: sample.relativeHumidityPercent,
                        precipitationMillimeters: sample.precipitationMillimeters,
                        weatherCode: sample.weatherCode,
                        windSpeedKilometersPerHour: sample.windSpeedKilometersPerHour,
                        sourceURL: "https://open-meteo.com/en/docs/historical-weather-api",
                        fetchedAt: now()
                    ))
                }
            }
            if categories.contains(.airQuality) {
                let samples = try await provider.airQuality(for: chunk)
                for sample in samples {
                    try await store.upsertAirQualityPoint(EnvironmentAirQualityPoint(
                        regionID: regionID,
                        observedAt: sample.observedAt,
                        dataKind: .historicalReanalysis,
                        provider: "Open-Meteo Air Quality",
                        europeanAQI: sample.europeanAQI,
                        usAQI: sample.usAQI,
                        pm10: sample.pm10,
                        pm2_5: sample.pm2_5,
                        nitrogenDioxide: sample.nitrogenDioxide,
                        ozone: sample.ozone,
                        sourceURL: "https://open-meteo.com/en/docs/air-quality-api",
                        fetchedAt: now()
                    ))
                }
            }
            guard chunkEnd < request.endDate,
                  let next = calendar.date(byAdding: .day, value: 1, to: chunkEnd) else { break }
            chunkStart = next
        }
    }
}
