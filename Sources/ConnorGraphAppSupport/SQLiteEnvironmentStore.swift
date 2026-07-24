import Foundation
import SQLite3
import ConnorGraphAgent

public enum EnvironmentStoreError: Error, LocalizedError, Sendable, Equatable {
    case openFailed(String)
    case sqlite(String)
    case invalidRecord(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): "无法打开环境数据库：\(message)"
        case .sqlite(let message): "环境数据库错误：\(message)"
        case .invalidRecord(let message): "无效环境记录：\(message)"
        }
    }
}

public struct StoredEnvironmentRegion: Sendable, Equatable {
    public var id: Int64
    public var gridCellID: String
    public var centerLatitude: Double
    public var centerLongitude: Double
    public var timeZoneIdentifier: String
    public var countryCode: String?
    public var administrativeArea: String?
    public var locality: String?
}

public struct EnvironmentWeatherPoint: Sendable, Equatable {
    public var regionID: Int64
    public var observedAt: Date
    public var dataKind: AgentEnvironmentDataKind
    public var provider: String
    public var condition: String?
    public var temperatureCelsius: Double?
    public var apparentTemperatureCelsius: Double?
    public var relativeHumidityPercent: Int?
    public var precipitationMillimeters: Double?
    public var precipitationProbabilityPercent: Int?
    public var weatherCode: Int?
    public var windSpeedKilometersPerHour: Double?
    public var sourceURL: String?
    public var fetchedAt: Date
    public var expiresAt: Date?

    public init(
        regionID: Int64,
        observedAt: Date,
        dataKind: AgentEnvironmentDataKind,
        provider: String,
        condition: String? = nil,
        temperatureCelsius: Double? = nil,
        apparentTemperatureCelsius: Double? = nil,
        relativeHumidityPercent: Int? = nil,
        precipitationMillimeters: Double? = nil,
        precipitationProbabilityPercent: Int? = nil,
        weatherCode: Int? = nil,
        windSpeedKilometersPerHour: Double? = nil,
        sourceURL: String? = nil,
        fetchedAt: Date,
        expiresAt: Date? = nil
    ) {
        self.regionID = regionID
        self.observedAt = observedAt
        self.dataKind = dataKind
        self.provider = provider
        self.condition = condition
        self.temperatureCelsius = temperatureCelsius
        self.apparentTemperatureCelsius = apparentTemperatureCelsius
        self.relativeHumidityPercent = relativeHumidityPercent
        self.precipitationMillimeters = precipitationMillimeters
        self.precipitationProbabilityPercent = precipitationProbabilityPercent
        self.weatherCode = weatherCode
        self.windSpeedKilometersPerHour = windSpeedKilometersPerHour
        self.sourceURL = sourceURL
        self.fetchedAt = fetchedAt
        self.expiresAt = expiresAt
    }
}

public struct EnvironmentAirQualityPoint: Sendable, Equatable {
    public var regionID: Int64
    public var observedAt: Date
    public var dataKind: AgentEnvironmentDataKind
    public var provider: String
    public var europeanAQI: Int?
    public var usAQI: Int?
    public var pm10: Double?
    public var pm2_5: Double?
    public var nitrogenDioxide: Double?
    public var ozone: Double?
    public var sourceURL: String?
    public var fetchedAt: Date

    public init(
        regionID: Int64,
        observedAt: Date,
        dataKind: AgentEnvironmentDataKind,
        provider: String,
        europeanAQI: Int? = nil,
        usAQI: Int? = nil,
        pm10: Double? = nil,
        pm2_5: Double? = nil,
        nitrogenDioxide: Double? = nil,
        ozone: Double? = nil,
        sourceURL: String? = nil,
        fetchedAt: Date
    ) {
        self.regionID = regionID
        self.observedAt = observedAt
        self.dataKind = dataKind
        self.provider = provider
        self.europeanAQI = europeanAQI
        self.usAQI = usAQI
        self.pm10 = pm10
        self.pm2_5 = pm2_5
        self.nitrogenDioxide = nitrogenDioxide
        self.ozone = ozone
        self.sourceURL = sourceURL
        self.fetchedAt = fetchedAt
    }
}

public actor SQLiteEnvironmentStore {
    private final class DatabaseHandle: @unchecked Sendable {
        let rawValue: OpaquePointer

        init(_ rawValue: OpaquePointer) { self.rawValue = rawValue }
        deinit { sqlite3_close(rawValue) }
    }

    private let database: DatabaseHandle

    private init(databaseURL: URL) throws {
        let fileManager = FileManager()
        try fileManager.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? databaseURL.path
            sqlite3_close(handle)
            throw EnvironmentStoreError.openFailed(message)
        }
        database = DatabaseHandle(handle)
    }

    public static func open(databaseURL: URL) async throws -> SQLiteEnvironmentStore {
        try await Task.detached {
            let store = try SQLiteEnvironmentStore(databaseURL: databaseURL)
            try await store.configure()
            return store
        }.value
    }

    private func configure() throws {
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
        try migrate()
    }

    @discardableResult
    public func upsertRegion(
        _ region: AgentEnvironmentRegion,
        timeZoneIdentifier: String,
        countryCode: String? = nil,
        administrativeArea: String? = nil,
        locality: String? = nil,
        now: Date = Date()
    ) throws -> Int64 {
        let sql = """
        INSERT INTO environment_regions (
            grid_system, grid_precision_version, grid_cell_id, center_latitude, center_longitude,
            timezone_identifier, country_code, administrative_area, locality, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(grid_system, grid_precision_version, grid_cell_id) DO UPDATE SET
            timezone_identifier = excluded.timezone_identifier,
            country_code = COALESCE(excluded.country_code, environment_regions.country_code),
            administrative_area = COALESCE(excluded.administrative_area, environment_regions.administrative_area),
            locality = COALESCE(excluded.locality, environment_regions.locality),
            updated_at = excluded.updated_at
        """
        try run(sql, bindings: [
            .text(AgentEnvironmentRegion.gridSystem), .integer(Int64(AgentEnvironmentRegion.gridPrecisionVersion)),
            .text(region.gridCellID), .real(region.centerLatitude), .real(region.centerLongitude),
            .text(timeZoneIdentifier), .optionalText(countryCode), .optionalText(administrativeArea),
            .optionalText(locality), .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970)
        ])
        return try regionID(forGridCellID: region.gridCellID)
    }

    public func upsertWeatherPoint(_ point: EnvironmentWeatherPoint) throws {
        guard !point.provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EnvironmentStoreError.invalidRecord("provider 不能为空")
        }
        let sql = """
        INSERT INTO environment_time_series_points (
            region_id, observed_at, data_kind, provider, condition, temperature_celsius,
            apparent_temperature_celsius, relative_humidity_percent, precipitation_millimeters,
            precipitation_probability_percent, weather_code, wind_speed_kph, source_url,
            fetched_at, expires_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(region_id, observed_at, data_kind, provider) DO UPDATE SET
            condition = excluded.condition,
            temperature_celsius = excluded.temperature_celsius,
            apparent_temperature_celsius = excluded.apparent_temperature_celsius,
            relative_humidity_percent = excluded.relative_humidity_percent,
            precipitation_millimeters = excluded.precipitation_millimeters,
            precipitation_probability_percent = excluded.precipitation_probability_percent,
            weather_code = excluded.weather_code,
            wind_speed_kph = excluded.wind_speed_kph,
            source_url = excluded.source_url,
            fetched_at = excluded.fetched_at,
            expires_at = excluded.expires_at
        """
        try run(sql, bindings: [
            .integer(point.regionID), .real(point.observedAt.timeIntervalSince1970), .text(point.dataKind.rawValue),
            .text(point.provider), .optionalText(point.condition), .optionalReal(point.temperatureCelsius),
            .optionalReal(point.apparentTemperatureCelsius), .optionalInteger(point.relativeHumidityPercent.map(Int64.init)),
            .optionalReal(point.precipitationMillimeters), .optionalInteger(point.precipitationProbabilityPercent.map(Int64.init)),
            .optionalInteger(point.weatherCode.map(Int64.init)), .optionalReal(point.windSpeedKilometersPerHour),
            .optionalText(point.sourceURL), .real(point.fetchedAt.timeIntervalSince1970),
            .optionalReal(point.expiresAt?.timeIntervalSince1970)
        ])
    }

    public func weatherPoints(regionID: Int64, from start: Date, through end: Date) throws -> [EnvironmentWeatherPoint] {
        let sql = """
        SELECT observed_at, data_kind, provider, condition, temperature_celsius,
               apparent_temperature_celsius, relative_humidity_percent, precipitation_millimeters,
               precipitation_probability_percent, weather_code, wind_speed_kph, source_url,
               fetched_at, expires_at
        FROM environment_time_series_points
        WHERE region_id = ? AND observed_at >= ? AND observed_at <= ?
        ORDER BY observed_at ASC, data_kind ASC, provider ASC
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind([.integer(regionID), .real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)], to: statement)
        var points: [EnvironmentWeatherPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let kindRaw = text(statement, 1), let kind = AgentEnvironmentDataKind(rawValue: kindRaw),
                  let provider = text(statement, 2) else { continue }
            points.append(EnvironmentWeatherPoint(
                regionID: regionID,
                observedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                dataKind: kind,
                provider: provider,
                condition: text(statement, 3),
                temperatureCelsius: optionalDouble(statement, 4),
                apparentTemperatureCelsius: optionalDouble(statement, 5),
                relativeHumidityPercent: optionalInt(statement, 6),
                precipitationMillimeters: optionalDouble(statement, 7),
                precipitationProbabilityPercent: optionalInt(statement, 8),
                weatherCode: optionalInt(statement, 9),
                windSpeedKilometersPerHour: optionalDouble(statement, 10),
                sourceURL: text(statement, 11),
                fetchedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 12)),
                expiresAt: optionalDouble(statement, 13).map(Date.init(timeIntervalSince1970:))
            ))
        }
        try checkStep(statement)
        return points
    }

    public func upsertAirQualityPoint(_ point: EnvironmentAirQualityPoint) throws {
        let sql = """
        INSERT INTO environment_air_quality_points (
            region_id, observed_at, data_kind, provider, european_aqi, us_aqi, pm10, pm2_5,
            nitrogen_dioxide, ozone, source_url, fetched_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(region_id, observed_at, data_kind, provider) DO UPDATE SET
            european_aqi = excluded.european_aqi,
            us_aqi = excluded.us_aqi,
            pm10 = excluded.pm10,
            pm2_5 = excluded.pm2_5,
            nitrogen_dioxide = excluded.nitrogen_dioxide,
            ozone = excluded.ozone,
            source_url = excluded.source_url,
            fetched_at = excluded.fetched_at
        """
        try run(sql, bindings: [
            .integer(point.regionID), .real(point.observedAt.timeIntervalSince1970), .text(point.dataKind.rawValue),
            .text(point.provider), .optionalInteger(point.europeanAQI.map(Int64.init)),
            .optionalInteger(point.usAQI.map(Int64.init)), .optionalReal(point.pm10), .optionalReal(point.pm2_5),
            .optionalReal(point.nitrogenDioxide), .optionalReal(point.ozone), .optionalText(point.sourceURL),
            .real(point.fetchedAt.timeIntervalSince1970)
        ])
    }

    public func airQualityPoints(regionID: Int64, from start: Date, through end: Date) throws -> [EnvironmentAirQualityPoint] {
        let sql = """
        SELECT observed_at, data_kind, provider, european_aqi, us_aqi, pm10, pm2_5,
               nitrogen_dioxide, ozone, source_url, fetched_at
        FROM environment_air_quality_points
        WHERE region_id = ? AND observed_at >= ? AND observed_at <= ?
        ORDER BY observed_at ASC, data_kind ASC, provider ASC
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind([.integer(regionID), .real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)], to: statement)
        var points: [EnvironmentAirQualityPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let kindRaw = text(statement, 1), let kind = AgentEnvironmentDataKind(rawValue: kindRaw),
                  let provider = text(statement, 2) else { continue }
            points.append(EnvironmentAirQualityPoint(
                regionID: regionID,
                observedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                dataKind: kind,
                provider: provider,
                europeanAQI: optionalInt(statement, 3),
                usAQI: optionalInt(statement, 4),
                pm10: optionalDouble(statement, 5),
                pm2_5: optionalDouble(statement, 6),
                nitrogenDioxide: optionalDouble(statement, 7),
                ozone: optionalDouble(statement, 8),
                sourceURL: text(statement, 9),
                fetchedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10))
            ))
        }
        try checkStep(statement)
        return points
    }

    public func region(gridCellID: String) throws -> StoredEnvironmentRegion? {
        let sql = """
        SELECT region_id, grid_cell_id, center_latitude, center_longitude, timezone_identifier,
               country_code, administrative_area, locality
        FROM environment_regions
        WHERE grid_system = ? AND grid_precision_version = ? AND grid_cell_id = ?
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind([.text(AgentEnvironmentRegion.gridSystem), .integer(Int64(AgentEnvironmentRegion.gridPrecisionVersion)), .text(gridCellID)], to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return StoredEnvironmentRegion(
            id: sqlite3_column_int64(statement, 0),
            gridCellID: text(statement, 1) ?? gridCellID,
            centerLatitude: sqlite3_column_double(statement, 2),
            centerLongitude: sqlite3_column_double(statement, 3),
            timeZoneIdentifier: text(statement, 4) ?? "UTC",
            countryCode: text(statement, 5),
            administrativeArea: text(statement, 6),
            locality: text(statement, 7)
        )
    }

    public func regions(matching placeName: String) throws -> [StoredEnvironmentRegion] {
        let normalized = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        let pattern = "%\(normalized.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
        let sql = """
        SELECT region_id, grid_cell_id, center_latitude, center_longitude, timezone_identifier,
               country_code, administrative_area, locality
        FROM environment_regions
        WHERE locality LIKE ? ESCAPE '\\' COLLATE NOCASE
           OR administrative_area LIKE ? ESCAPE '\\' COLLATE NOCASE
           OR country_code = ? COLLATE NOCASE
           OR grid_cell_id = ?
        ORDER BY updated_at DESC
        LIMIT 20
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind([.text(pattern), .text(pattern), .text(normalized), .text(normalized)], to: statement)
        var regions: [StoredEnvironmentRegion] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            regions.append(StoredEnvironmentRegion(
                id: sqlite3_column_int64(statement, 0),
                gridCellID: text(statement, 1) ?? "",
                centerLatitude: sqlite3_column_double(statement, 2),
                centerLongitude: sqlite3_column_double(statement, 3),
                timeZoneIdentifier: text(statement, 4) ?? "UTC",
                countryCode: text(statement, 5),
                administrativeArea: text(statement, 6),
                locality: text(statement, 7)
            ))
        }
        try checkStep(statement)
        return regions
    }

    private func regionID(forGridCellID gridCellID: String) throws -> Int64 {
        guard let id = try region(gridCellID: gridCellID)?.id else {
            throw EnvironmentStoreError.sqlite("写入区域后无法读取 region_id")
        }
        return id
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS environment_schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS environment_regions (
            region_id INTEGER PRIMARY KEY AUTOINCREMENT,
            grid_system TEXT NOT NULL,
            grid_precision_version INTEGER NOT NULL,
            grid_cell_id TEXT NOT NULL,
            center_latitude REAL NOT NULL,
            center_longitude REAL NOT NULL,
            timezone_identifier TEXT NOT NULL,
            country_code TEXT,
            administrative_area TEXT,
            locality TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(grid_system, grid_precision_version, grid_cell_id)
        );
        CREATE TABLE IF NOT EXISTS environment_time_series_points (
            point_id INTEGER PRIMARY KEY AUTOINCREMENT,
            region_id INTEGER NOT NULL REFERENCES environment_regions(region_id),
            observed_at REAL NOT NULL,
            data_kind TEXT NOT NULL CHECK(data_kind IN ('current_observation', 'forecast', 'historical_observation', 'historical_reanalysis')),
            provider TEXT NOT NULL,
            condition TEXT,
            temperature_celsius REAL,
            apparent_temperature_celsius REAL,
            relative_humidity_percent INTEGER,
            precipitation_millimeters REAL,
            precipitation_probability_percent INTEGER,
            weather_code INTEGER,
            wind_speed_kph REAL,
            source_url TEXT,
            fetched_at REAL NOT NULL,
            expires_at REAL,
            UNIQUE(region_id, observed_at, data_kind, provider)
        );
        CREATE INDEX IF NOT EXISTS environment_time_series_range_idx
            ON environment_time_series_points(region_id, observed_at, data_kind);
        CREATE TABLE IF NOT EXISTS environment_air_quality_points (
            point_id INTEGER PRIMARY KEY AUTOINCREMENT,
            region_id INTEGER NOT NULL REFERENCES environment_regions(region_id),
            observed_at REAL NOT NULL,
            data_kind TEXT NOT NULL CHECK(data_kind IN ('current_observation', 'forecast', 'historical_observation', 'historical_reanalysis')),
            provider TEXT NOT NULL,
            european_aqi INTEGER,
            us_aqi INTEGER,
            pm10 REAL,
            pm2_5 REAL,
            nitrogen_dioxide REAL,
            ozone REAL,
            source_url TEXT,
            fetched_at REAL NOT NULL,
            UNIQUE(region_id, observed_at, data_kind, provider)
        );
        CREATE INDEX IF NOT EXISTS environment_air_quality_range_idx
            ON environment_air_quality_points(region_id, observed_at, data_kind);
        CREATE TABLE IF NOT EXISTS environment_alerts (
            alert_id TEXT PRIMARY KEY,
            region_id INTEGER NOT NULL REFERENCES environment_regions(region_id),
            provider TEXT NOT NULL,
            severity TEXT NOT NULL,
            title TEXT NOT NULL,
            description TEXT,
            starts_at REAL,
            ends_at REAL,
            status TEXT NOT NULL,
            source_url TEXT,
            fetched_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS environment_notice_state (
            notice_key TEXT PRIMARY KEY,
            region_id INTEGER NOT NULL REFERENCES environment_regions(region_id),
            category TEXT NOT NULL,
            last_noticed_at REAL NOT NULL,
            last_value TEXT
        );
        CREATE TABLE IF NOT EXISTS environment_history_queries (
            query_id TEXT PRIMARY KEY,
            region_id INTEGER NOT NULL REFERENCES environment_regions(region_id),
            category TEXT NOT NULL,
            starts_at REAL NOT NULL,
            ends_at REAL NOT NULL,
            provider TEXT NOT NULL,
            status TEXT NOT NULL,
            error_category TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(region_id, category, starts_at, ends_at, provider)
        );
        CREATE TABLE IF NOT EXISTS environment_provider_state (
            provider TEXT NOT NULL,
            state_key TEXT NOT NULL,
            state_value TEXT NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY(provider, state_key)
        );
        INSERT OR IGNORE INTO environment_schema_migrations(version, applied_at)
            VALUES (1, unixepoch());
        """)
    }

    private enum Binding {
        case integer(Int64)
        case real(Double)
        case text(String)
        case null

        static func optionalText(_ value: String?) -> Binding { value.map(Binding.text) ?? .null }
        static func optionalReal(_ value: Double?) -> Binding { value.map(Binding.real) ?? .null }
        static func optionalInteger(_ value: Int64?) -> Binding { value.map(Binding.integer) ?? .null }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database.rawValue, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    private func run(_ sql: String, bindings: [Binding]) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database.rawValue, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw lastError() }
        return statement
    }

    private func bind(_ bindings: [Binding], to statement: OpaquePointer) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .integer(let value): result = sqlite3_bind_int64(statement, index, value)
            case .real(let value): result = sqlite3_bind_double(statement, index, value)
            case .text(let value): result = sqlite3_bind_text(statement, index, value, -1, ENVIRONMENT_SQLITE_TRANSIENT)
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw lastError() }
        }
    }

    private func checkStep(_ statement: OpaquePointer) throws {
        let result = sqlite3_errcode(database.rawValue)
        guard result == SQLITE_OK || result == SQLITE_DONE else { throw lastError() }
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private func optionalDouble(_ statement: OpaquePointer, _ column: Int32) -> Double? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_double(statement, column)
    }

    private func optionalInt(_ statement: OpaquePointer, _ column: Int32) -> Int? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, column))
    }

    private func lastError() -> EnvironmentStoreError {
        .sqlite(String(cString: sqlite3_errmsg(database.rawValue)))
    }
}

private let ENVIRONMENT_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
