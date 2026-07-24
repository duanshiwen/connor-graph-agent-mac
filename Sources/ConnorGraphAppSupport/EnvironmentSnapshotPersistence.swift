import Foundation
import ConnorGraphAgent

public protocol EnvironmentSnapshotPersisting: Sendable {
    func record(_ snapshot: AgentEnvironmentSnapshot) async
}

public actor EnvironmentSnapshotPersistence: EnvironmentSnapshotPersisting {
    private let storeTask: Task<SQLiteEnvironmentStore, Error>

    public init(databaseURL: URL) {
        storeTask = Task {
            try await SQLiteEnvironmentStore.open(databaseURL: databaseURL)
        }
    }

    public func record(_ snapshot: AgentEnvironmentSnapshot) async {
        guard snapshot.location.status == .available || snapshot.location.status == .stale,
              let gridCellID = snapshot.location.gridCellID,
              let latitude = snapshot.location.latitude,
              let longitude = snapshot.location.longitude else { return }
        let region = AgentEnvironmentRegion(
            gridCellID: gridCellID,
            centerLatitude: latitude,
            centerLongitude: longitude
        )
        do {
            let store = try await storeTask.value
            let regionID = try await store.upsertRegion(
                region,
                timeZoneIdentifier: snapshot.localTime.timeZoneIdentifier,
                administrativeArea: snapshot.location.administrativeArea,
                locality: snapshot.location.locality,
                now: snapshot.capturedAt
            )
            try await persistWeather(snapshot.weather, snapshot: snapshot, regionID: regionID, store: store)
        } catch {
            // Environment persistence is best effort and must never block the user run.
        }
    }

    private func persistWeather(
        _ weather: AgentEnvironmentWeather,
        snapshot: AgentEnvironmentSnapshot,
        regionID: Int64,
        store: SQLiteEnvironmentStore
    ) async throws {
        guard weather.status == .available || weather.status == .stale else { return }
        let provider = weather.source ?? "Open-Meteo"
        let fetchedAt = weather.updatedAt ?? snapshot.capturedAt
        try await store.upsertWeatherPoint(EnvironmentWeatherPoint(
            regionID: regionID,
            observedAt: snapshot.capturedAt,
            dataKind: .currentObservation,
            provider: provider,
            condition: weather.condition,
            temperatureCelsius: weather.temperatureCelsius,
            apparentTemperatureCelsius: weather.apparentTemperatureCelsius,
            relativeHumidityPercent: weather.relativeHumidityPercent,
            precipitationMillimeters: weather.precipitationMillimeters,
            windSpeedKilometersPerHour: weather.windSpeedKilometersPerHour,
            sourceURL: weather.sourceURL,
            fetchedAt: fetchedAt,
            expiresAt: weather.expiresAt
        ))

        guard let timeZone = TimeZone(identifier: snapshot.localTime.timeZoneIdentifier) else { return }
        for hourly in weather.hourlyForecast {
            guard let observedAt = Self.date(fromLocalTimestamp: hourly.localTime, timeZone: timeZone) else { continue }
            try await store.upsertWeatherPoint(EnvironmentWeatherPoint(
                regionID: regionID,
                observedAt: observedAt,
                dataKind: .forecast,
                provider: provider,
                temperatureCelsius: hourly.temperatureCelsius,
                precipitationProbabilityPercent: hourly.precipitationProbabilityPercent,
                weatherCode: hourly.weatherCode,
                sourceURL: weather.sourceURL,
                fetchedAt: fetchedAt,
                expiresAt: weather.expiresAt
            ))
        }
    }

    private static func date(fromLocalTimestamp value: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: value)
    }
}
