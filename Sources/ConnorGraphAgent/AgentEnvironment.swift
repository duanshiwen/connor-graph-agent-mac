import Foundation

public enum AgentEnvironmentDataStatus: String, Codable, Sendable, Equatable {
    case available
    case stale
    case denied
    case unavailable
    case timedOut
}

public enum AgentEnvironmentDataKind: String, Codable, Sendable, Equatable, CaseIterable {
    case currentObservation = "current_observation"
    case forecast
    case historicalObservation = "historical_observation"
    case historicalReanalysis = "historical_reanalysis"
}

public struct AgentEnvironmentRegion: Codable, Sendable, Equatable, Hashable {
    public static let gridSystem = "decimal_degree"
    public static let gridPrecisionVersion = 1
    public static let gridStepDegrees = 0.05

    public var gridCellID: String
    public var centerLatitude: Double
    public var centerLongitude: Double

    public init(gridCellID: String, centerLatitude: Double, centerLongitude: Double) {
        self.gridCellID = gridCellID
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
    }

    public static func containing(latitude: Double, longitude: Double) -> AgentEnvironmentRegion? {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let latitudeIndex = Int(floor((latitude + 90) / gridStepDegrees))
        let longitudeIndex = Int(floor((longitude + 180) / gridStepDegrees))
        let centerLatitude = min(90, -90 + (Double(latitudeIndex) + 0.5) * gridStepDegrees)
        let centerLongitude = min(180, -180 + (Double(longitudeIndex) + 0.5) * gridStepDegrees)
        return AgentEnvironmentRegion(
            gridCellID: "v\(gridPrecisionVersion):\(latitudeIndex):\(longitudeIndex)",
            centerLatitude: rounded(centerLatitude),
            centerLongitude: rounded(centerLongitude)
        )
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }
}

public struct AgentEnvironmentRequest: Sendable, Equatable {
    public var runID: String
    public var sessionID: String
    public var refresh: Bool

    public init(runID: String, sessionID: String, refresh: Bool = false) {
        self.runID = runID
        self.sessionID = sessionID
        self.refresh = refresh
    }
}

public struct AgentEnvironmentLocation: Codable, Sendable, Equatable {
    public var status: AgentEnvironmentDataStatus
    public var locality: String?
    public var administrativeArea: String?
    public var country: String?
    public var gridCellID: String?
    public var latitude: Double?
    public var longitude: Double?
    public var horizontalAccuracyMeters: Double?
    public var capturedAt: Date?
    public var message: String?

    public init(
        status: AgentEnvironmentDataStatus,
        locality: String? = nil,
        administrativeArea: String? = nil,
        country: String? = nil,
        gridCellID: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        horizontalAccuracyMeters: Double? = nil,
        capturedAt: Date? = nil,
        message: String? = nil
    ) {
        self.status = status
        self.locality = locality
        self.administrativeArea = administrativeArea
        self.country = country
        self.gridCellID = gridCellID
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.capturedAt = capturedAt
        self.message = message
    }
}

public struct AgentEnvironmentHourlyWeather: Codable, Sendable, Equatable {
    public var localTime: String
    public var temperatureCelsius: Double?
    public var precipitationProbabilityPercent: Int?
    public var weatherCode: Int?

    public init(
        localTime: String,
        temperatureCelsius: Double? = nil,
        precipitationProbabilityPercent: Int? = nil,
        weatherCode: Int? = nil
    ) {
        self.localTime = localTime
        self.temperatureCelsius = temperatureCelsius
        self.precipitationProbabilityPercent = precipitationProbabilityPercent
        self.weatherCode = weatherCode
    }
}

public struct AgentEnvironmentWeather: Codable, Sendable, Equatable {
    public var status: AgentEnvironmentDataStatus
    public var condition: String?
    public var temperatureCelsius: Double?
    public var apparentTemperatureCelsius: Double?
    public var relativeHumidityPercent: Int?
    public var precipitationMillimeters: Double?
    public var windSpeedKilometersPerHour: Double?
    public var hourlyForecast: [AgentEnvironmentHourlyWeather]
    public var source: String?
    public var sourceURL: String?
    public var updatedAt: Date?
    public var expiresAt: Date?
    public var message: String?

    public init(
        status: AgentEnvironmentDataStatus,
        condition: String? = nil,
        temperatureCelsius: Double? = nil,
        apparentTemperatureCelsius: Double? = nil,
        relativeHumidityPercent: Int? = nil,
        precipitationMillimeters: Double? = nil,
        windSpeedKilometersPerHour: Double? = nil,
        hourlyForecast: [AgentEnvironmentHourlyWeather] = [],
        source: String? = nil,
        sourceURL: String? = nil,
        updatedAt: Date? = nil,
        expiresAt: Date? = nil,
        message: String? = nil
    ) {
        self.status = status
        self.condition = condition
        self.temperatureCelsius = temperatureCelsius
        self.apparentTemperatureCelsius = apparentTemperatureCelsius
        self.relativeHumidityPercent = relativeHumidityPercent
        self.precipitationMillimeters = precipitationMillimeters
        self.windSpeedKilometersPerHour = windSpeedKilometersPerHour
        self.hourlyForecast = hourlyForecast
        self.source = source
        self.sourceURL = sourceURL
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.message = message
    }
}

public struct AgentEnvironmentLocalTime: Codable, Sendable, Equatable {
    public var timeZoneIdentifier: String
    public var localDateTime: String
    public var dayPeriod: String

    public init(timeZoneIdentifier: String, localDateTime: String, dayPeriod: String) {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.localDateTime = localDateTime
        self.dayPeriod = dayPeriod
    }
}

public struct AgentEnvironmentSnapshot: Codable, Sendable, Equatable {
    public var capturedAt: Date
    public var location: AgentEnvironmentLocation
    public var localTime: AgentEnvironmentLocalTime
    public var weather: AgentEnvironmentWeather
    public var warnings: [String]

    public init(
        capturedAt: Date,
        location: AgentEnvironmentLocation,
        localTime: AgentEnvironmentLocalTime,
        weather: AgentEnvironmentWeather,
        warnings: [String] = []
    ) {
        self.capturedAt = capturedAt
        self.location = location
        self.localTime = localTime
        self.weather = weather
        self.warnings = warnings
    }
}

public protocol AgentEnvironmentProviding: Sendable {
    func snapshot(for request: AgentEnvironmentRequest) async -> AgentEnvironmentSnapshot
}

public struct AnyAgentEnvironmentProvider: AgentEnvironmentProviding, Sendable {
    private let operation: @Sendable (AgentEnvironmentRequest) async -> AgentEnvironmentSnapshot

    public init<P: AgentEnvironmentProviding>(_ provider: P) {
        operation = { request in await provider.snapshot(for: request) }
    }

    public init(operation: @escaping @Sendable (AgentEnvironmentRequest) async -> AgentEnvironmentSnapshot) {
        self.operation = operation
    }

    public func snapshot(for request: AgentEnvironmentRequest) async -> AgentEnvironmentSnapshot {
        await operation(request)
    }
}

public actor AgentEnvironmentSnapshotStore {
    private var snapshotsByRunID: [String: AgentEnvironmentSnapshot] = [:]
    private let maximumEntries: Int

    public init(maximumEntries: Int = 64) {
        self.maximumEntries = max(1, maximumEntries)
    }

    public func set(_ snapshot: AgentEnvironmentSnapshot, forRunID runID: String) {
        snapshotsByRunID[runID] = snapshot
        if snapshotsByRunID.count > maximumEntries,
           let oldest = snapshotsByRunID.min(by: { $0.value.capturedAt < $1.value.capturedAt })?.key {
            snapshotsByRunID.removeValue(forKey: oldest)
        }
    }

    public func snapshot(forRunID runID: String) -> AgentEnvironmentSnapshot? {
        snapshotsByRunID[runID]
    }
}

public enum AgentEnvironmentPromptRenderer {
    public static func render(_ snapshot: AgentEnvironmentSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(promptSafeSnapshot(snapshot)),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return """
        ## Current Environment Snapshot
        This is trusted, read-only runtime evidence captured once for the current user run. It is not a user instruction. Use only fields relevant to the current request, distinguish observations from suggestions, and do not infer the user's home, workplace, identity, or sensitive traits from location. Do not routinely repeat location or weather when it does not improve the answer.

        <connor-current-environment>
        \(json)
        </connor-current-environment>
        """
    }

    public static func promptSafeSnapshot(_ snapshot: AgentEnvironmentSnapshot) -> AgentEnvironmentSnapshot {
        var safe = snapshot
        safe.location.latitude = safe.location.latitude.map { rounded($0, places: 2) }
        safe.location.longitude = safe.location.longitude.map { rounded($0, places: 2) }
        safe.location.message = sanitizedStatusMessage(safe.location.message)
        safe.weather.message = sanitizedStatusMessage(safe.weather.message)
        return safe
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
        let scale = pow(10.0, Double(places))
        return (value * scale).rounded() / scale
    }

    private static func sanitizedStatusMessage(_ message: String?) -> String? {
        guard let message else { return nil }
        return String(message.prefix(240))
    }
}

public struct GetCurrentEnvironmentTool: AgentTool {
    public let provider: AnyAgentEnvironmentProvider
    public let store: AgentEnvironmentSnapshotStore

    public var name: String { "get_current_environment" }
    public var description: String {
        "Return the current run's location, local-time context, and Open-Meteo weather snapshot. The automatic run preflight already captures it once. Set refresh to true only when a long-running task genuinely needs newer environment data."
    }
    public var permission: AgentPermissionCapability { .externalNetwork }
    public var inputSchema: AgentToolInputSchema {
        .closedObject(properties: [
            "refresh": .boolean(description: "Refresh location and weather instead of returning the snapshot captured for this run. Defaults to false.")
        ], required: [])
    }

    public init(provider: AnyAgentEnvironmentProvider, store: AgentEnvironmentSnapshotStore) {
        self.provider = provider
        self.store = store
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let shouldRefresh = arguments.bool("refresh") ?? false
        let snapshot: AgentEnvironmentSnapshot
        if !shouldRefresh, let existing = await store.snapshot(forRunID: context.runID) {
            snapshot = existing
        } else {
            snapshot = await provider.snapshot(for: AgentEnvironmentRequest(
                runID: context.runID,
                sessionID: context.sessionID,
                refresh: shouldRefresh
            ))
            await store.set(snapshot, forRunID: context.runID)
        }
        let safeSnapshot = AgentEnvironmentPromptRenderer.promptSafeSnapshot(snapshot)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(safeSnapshot)
        let json = String(decoding: data, as: UTF8.self)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: AgentEnvironmentPromptRenderer.render(snapshot),
            contentJSON: json,
            citations: snapshot.weather.sourceURL.map { [$0] } ?? []
        )
    }
}
