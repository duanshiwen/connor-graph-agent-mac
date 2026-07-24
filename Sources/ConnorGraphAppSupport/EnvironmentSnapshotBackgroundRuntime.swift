import Foundation
import SQLite3
import ConnorGraphAgent

public struct EnvironmentSnapshotBackgroundRuntime: Sendable {
    public var databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public func execute(toolName: String, arguments: AgentToolArguments) throws -> String {
        let places: [String]
        if toolName == "environment_history_compare" {
            places = (arguments.array("places") ?? []).compactMap(\.stringValue)
            guard (2...4).contains(places.count) else {
                throw MemoryOSBackgroundToolExecutionError.invalidArguments("places must contain two to four explicit place names")
            }
        } else {
            guard let place = arguments.string("place"), !place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MemoryOSBackgroundToolExecutionError.invalidArguments("place is required")
            }
            places = [place]
        }
        guard let start = try arguments.iso8601Date("start"), let end = try arguments.iso8601Date("end"), start <= end else {
            throw MemoryOSBackgroundToolExecutionError.invalidArguments("start and end must be an ordered ISO-8601 range")
        }
        let categories = Set((arguments.array("categories") ?? []).compactMap(\.stringValue))
        guard !categories.isEmpty, categories.isSubset(of: Set(EnvironmentHistoryCategory.allCases.map(\.rawValue))) else {
            throw MemoryOSBackgroundToolExecutionError.invalidArguments("categories must contain weather or air_quality")
        }
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return try encode(places: places, start: start, end: end, records: [], truncated: false)
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            sqlite3_close(database)
            throw MemoryOSBackgroundToolExecutionError.toolExecutionFailed("environment snapshot database is unavailable")
        }
        defer { sqlite3_close(database) }
        var records: [[String: Any]] = []
        for place in places {
            if categories.contains(EnvironmentHistoryCategory.weather.rawValue) {
                records += try weatherRecords(database: database, place: place, start: start, end: end)
            }
            if categories.contains(EnvironmentHistoryCategory.airQuality.rawValue) {
                records += try airQualityRecords(database: database, place: place, start: start, end: end)
            }
        }
        records.sort { ($0["queried_at"] as? Double ?? 0) < ($1["queried_at"] as? Double ?? 0) }
        let truncated = records.count > 500
        return try encode(places: places, start: start, end: end, records: Array(records.prefix(500)), truncated: truncated)
    }

    private func weatherRecords(database: OpaquePointer, place: String, start: Date, end: Date) throws -> [[String: Any]] {
        try rows(
            database: database,
            sql: """
            SELECT r.grid_cell_id, r.center_latitude, r.center_longitude, r.timezone_identifier,
                   r.locality, r.administrative_area, p.observed_at, p.data_kind, p.provider,
                   p.temperature_celsius, p.apparent_temperature_celsius, p.relative_humidity_percent,
                   p.precipitation_millimeters, p.wind_speed_kph
            FROM environment_time_series_points p
            JOIN environment_regions r ON r.region_id = p.region_id
            WHERE (r.locality LIKE ? COLLATE NOCASE OR r.administrative_area LIKE ? COLLATE NOCASE OR r.grid_cell_id = ?)
              AND p.observed_at >= ? AND p.observed_at <= ?
            ORDER BY p.observed_at ASC LIMIT 501
            """,
            place: place,
            start: start,
            end: end
        ) { statement in
            compact([
                "category": "weather",
                "grid_cell_id": text(statement, 0),
                "grid_center_latitude": number(statement, 1),
                "grid_center_longitude": number(statement, 2),
                "timezone": text(statement, 3),
                "locality": text(statement, 4),
                "administrative_area": text(statement, 5),
                "queried_at": number(statement, 6),
                "data_kind": text(statement, 7),
                "provider": text(statement, 8),
                "temperature_celsius": number(statement, 9),
                "apparent_temperature_celsius": number(statement, 10),
                "relative_humidity_percent": integer(statement, 11),
                "precipitation_millimeters": number(statement, 12),
                "wind_speed_kph": number(statement, 13)
            ])
        }
    }

    private func airQualityRecords(database: OpaquePointer, place: String, start: Date, end: Date) throws -> [[String: Any]] {
        try rows(
            database: database,
            sql: """
            SELECT r.grid_cell_id, r.center_latitude, r.center_longitude, r.timezone_identifier,
                   r.locality, r.administrative_area, p.observed_at, p.data_kind, p.provider,
                   p.european_aqi, p.us_aqi, p.pm10, p.pm2_5, p.nitrogen_dioxide, p.ozone
            FROM environment_air_quality_points p
            JOIN environment_regions r ON r.region_id = p.region_id
            WHERE (r.locality LIKE ? COLLATE NOCASE OR r.administrative_area LIKE ? COLLATE NOCASE OR r.grid_cell_id = ?)
              AND p.observed_at >= ? AND p.observed_at <= ?
            ORDER BY p.observed_at ASC LIMIT 501
            """,
            place: place,
            start: start,
            end: end
        ) { statement in
            compact([
                "category": "air_quality",
                "grid_cell_id": text(statement, 0),
                "grid_center_latitude": number(statement, 1),
                "grid_center_longitude": number(statement, 2),
                "timezone": text(statement, 3),
                "locality": text(statement, 4),
                "administrative_area": text(statement, 5),
                "queried_at": number(statement, 6),
                "data_kind": text(statement, 7),
                "provider": text(statement, 8),
                "european_aqi": integer(statement, 9),
                "us_aqi": integer(statement, 10),
                "pm10": number(statement, 11),
                "pm2_5": number(statement, 12),
                "nitrogen_dioxide": number(statement, 13),
                "ozone": number(statement, 14)
            ])
        }
    }

    private func rows(
        database: OpaquePointer,
        sql: String,
        place: String,
        start: Date,
        end: Date,
        decode: (OpaquePointer) -> [String: Any]
    ) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MemoryOSBackgroundToolExecutionError.toolExecutionFailed("environment snapshot query could not be prepared")
        }
        defer { sqlite3_finalize(statement) }
        let pattern = "%\(place)%"
        sqlite3_bind_text(statement, 1, pattern, -1, ENVIRONMENT_BACKGROUND_SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, pattern, -1, ENVIRONMENT_BACKGROUND_SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, place, -1, ENVIRONMENT_BACKGROUND_SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 4, start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 5, end.timeIntervalSince1970)
        var result: [[String: Any]] = []
        while sqlite3_step(statement) == SQLITE_ROW { result.append(decode(statement)) }
        guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
            throw MemoryOSBackgroundToolExecutionError.toolExecutionFailed("environment snapshot query failed")
        }
        return result
    }

    private func encode(places: [String], start: Date, end: Date, records: [[String: Any]], truncated: Bool) throws -> String {
        let formatter = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "sampling_model": "provider_query_snapshots",
            "continuous_coverage": false,
            "places": places,
            "start": formatter.string(from: start),
            "end": formatter.string(from: end),
            "record_count": records.count,
            "records": records,
            "truncated": truncated,
            "evidence_boundary": "Context evidence only. Do not infer user location, profile, health, preference, home, workplace, or causation."
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), as: UTF8.self)
    }

    private func compact(_ values: [String: Any?]) -> [String: Any] {
        values.reduce(into: [:]) { if let value = $1.value { $0[$1.key] = value } }
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL, let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private func number(_ statement: OpaquePointer, _ column: Int32) -> Double? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_double(statement, column)
    }

    private func integer(_ statement: OpaquePointer, _ column: Int32) -> Int? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, column))
    }
}

private let ENVIRONMENT_BACKGROUND_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
