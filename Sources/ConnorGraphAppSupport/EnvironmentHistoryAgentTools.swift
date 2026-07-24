import Foundation
import ConnorGraphAgent

private struct EnvironmentMetricSummary: Codable, Sendable, Equatable {
    var sampleCount: Int
    var queryTimestamps: [Date]
    var dataKinds: [String]
    var minimumTemperatureCelsius: Double?
    var maximumTemperatureCelsius: Double?
    var averageTemperatureCelsius: Double?
    var totalPrecipitationMillimeters: Double?
    var maximumWindSpeedKilometersPerHour: Double?
    var maximumEuropeanAQI: Int?
    var maximumUSAQI: Int?
    var averagePM2_5: Double?
}

private struct EnvironmentRegionToolSummary: Codable, Sendable, Equatable {
    var gridCellID: String
    var gridCenterLatitude: Double
    var gridCenterLongitude: Double
    var timeZoneIdentifier: String
    var locality: String?
    var administrativeArea: String?
}

private struct EnvironmentHistoryToolSummary: Codable, Sendable, Equatable {
    var place: String
    var regions: [EnvironmentRegionToolSummary]
    var gridStepDegrees: Double
    var timeZoneIdentifier: String
    var startDate: Date
    var endDate: Date
    var weather: EnvironmentMetricSummary?
    var airQuality: EnvironmentMetricSummary?
    var evidenceBoundary: String
}

private enum EnvironmentHistoryToolSupport {
    static let categorySchema = AgentToolInputSchema.array(
        items: .stringEnumeration(
            values: EnvironmentHistoryCategory.allCases.map(\.rawValue),
            description: "Environment category."
        ),
        description: "One or more environment categories."
    )

    static func parse(_ arguments: AgentToolArguments) throws -> (String, Date, Date, Set<EnvironmentHistoryCategory>) {
        guard let place = arguments.string("place")?.trimmingCharacters(in: .whitespacesAndNewlines), place.count >= 2 else {
            throw AgentToolError.invalidArguments("place must explicitly name a location")
        }
        guard let start = try arguments.iso8601Date("start"), let end = try arguments.iso8601Date("end") else {
            throw AgentToolError.invalidArguments("start and end are required ISO-8601 timestamps")
        }
        guard start <= end else { throw AgentToolError.invalidArguments("start must be before or equal to end") }
        let categories = Set((arguments.array("categories") ?? []).compactMap(\.stringValue).compactMap(EnvironmentHistoryCategory.init(rawValue:)))
        guard !categories.isEmpty else { throw AgentToolError.invalidArguments("categories must not be empty") }
        return (place, start, end, categories)
    }

    static func summary(place: String, result: EnvironmentHistoryResult) -> EnvironmentHistoryToolSummary {
        let weatherSummary = result.weather.isEmpty ? nil : metricSummary(
            timestamps: result.weather.map(\.observedAt),
            dataKinds: result.weather.map(\.dataKind),
            temperatures: result.weather.compactMap(\.temperatureCelsius),
            precipitation: result.weather.compactMap(\.precipitationMillimeters),
            wind: result.weather.compactMap(\.windSpeedKilometersPerHour)
        )
        let airSummary = result.airQuality.isEmpty ? nil : metricSummary(
            timestamps: result.airQuality.map(\.observedAt),
            dataKinds: result.airQuality.map(\.dataKind),
            europeanAQI: result.airQuality.compactMap(\.europeanAQI),
            usAQI: result.airQuality.compactMap(\.usAQI),
            pm2_5: result.airQuality.compactMap(\.pm2_5)
        )
        return EnvironmentHistoryToolSummary(
            place: place,
            regions: result.regions.map {
                EnvironmentRegionToolSummary(
                    gridCellID: $0.gridCellID,
                    gridCenterLatitude: $0.centerLatitude,
                    gridCenterLongitude: $0.centerLongitude,
                    timeZoneIdentifier: $0.timeZoneIdentifier,
                    locality: $0.locality,
                    administrativeArea: $0.administrativeArea
                )
            },
            gridStepDegrees: AgentEnvironmentRegion.gridStepDegrees,
            timeZoneIdentifier: result.regions.first?.timeZoneIdentifier ?? "UTC",
            startDate: result.startDate,
            endDate: result.endDate,
            weather: weatherSummary,
            airQuality: airSummary,
            evidenceBoundary: "Sparse snapshots captured only when Connor actually queried the provider. This is not continuous coverage. Correlation is not causation and this data must not be used to infer user location, preferences, health, home, or workplace."
        )
    }

    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func metricSummary(
        timestamps: [Date],
        dataKinds: [AgentEnvironmentDataKind],
        temperatures: [Double] = [],
        precipitation: [Double] = [],
        wind: [Double] = [],
        europeanAQI: [Int] = [],
        usAQI: [Int] = [],
        pm2_5: [Double] = []
    ) -> EnvironmentMetricSummary {
        EnvironmentMetricSummary(
            sampleCount: Set(timestamps).count,
            queryTimestamps: Array(Set(timestamps).sorted().prefix(200)),
            dataKinds: Set(dataKinds.map(\.rawValue)).sorted(),
            minimumTemperatureCelsius: temperatures.min(),
            maximumTemperatureCelsius: temperatures.max(),
            averageTemperatureCelsius: average(temperatures),
            totalPrecipitationMillimeters: precipitation.isEmpty ? nil : precipitation.reduce(0, +),
            maximumWindSpeedKilometersPerHour: wind.max(),
            maximumEuropeanAQI: europeanAQI.max(),
            maximumUSAQI: usAQI.max(),
            averagePM2_5: average(pm2_5)
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

public struct EnvironmentHistoryCoverageTool: AgentTool {
    public let service: EnvironmentHistoryService
    public var name: String { "environment_history_coverage" }
    public var description: String { "Check which sparse environment snapshots Connor actually recorded for an explicitly named place and time range. Never fetches or reconstructs missing history." }
    public var permission: AgentPermissionCapability { .readSession }
    public var inputSchema: AgentToolInputSchema {
        .closedObject(properties: [
            "place": .string(description: "Explicit place name supplied by the user or reliable task evidence; never infer it from current location."),
            "start": .string(description: "Inclusive ISO-8601 start timestamp."),
            "end": .string(description: "Inclusive ISO-8601 end timestamp."),
            "categories": EnvironmentHistoryToolSupport.categorySchema
        ], required: ["place", "start", "end", "categories"])
    }

    public init(service: EnvironmentHistoryService) { self.service = service }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let (place, start, end, categories) = try EnvironmentHistoryToolSupport.parse(arguments)
        guard let result = try await service.query(placeName: place, startDate: start, endDate: end, categories: categories) else {
            throw AgentToolError.invalidArguments("No recorded coarse environment region matches the explicit place")
        }
        let summary = EnvironmentHistoryToolSupport.summary(place: place, result: result)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Returned local historical environment coverage only; missing intervals were not fetched.",
            contentJSON: try EnvironmentHistoryToolSupport.encode(summary)
        )
    }
}

public struct EnvironmentHistoryQueryTool: AgentTool {
    public let service: EnvironmentHistoryService
    public var name: String { "environment_history_query" }
    public var description: String { "Query sparse weather or air-quality snapshots Connor actually recorded for an explicitly named place and time range. Never backfills missing intervals and returns bounded deterministic statistics with query timestamps." }
    public var permission: AgentPermissionCapability { .readSession }
    public var inputSchema: AgentToolInputSchema {
        EnvironmentHistoryCoverageTool(service: service).inputSchema
    }

    public init(service: EnvironmentHistoryService) { self.service = service }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let (place, start, end, categories) = try EnvironmentHistoryToolSupport.parse(arguments)
        guard let result = try await service.query(placeName: place, startDate: start, endDate: end, categories: categories) else {
            throw AgentToolError.invalidArguments("No recorded coarse environment region matches the explicit place")
        }
        let summary = EnvironmentHistoryToolSupport.summary(place: place, result: result)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Returned sparse environment snapshots captured at actual provider query times. Missing intervals were not reconstructed.",
            contentJSON: try EnvironmentHistoryToolSupport.encode(summary)
        )
    }
}

public struct EnvironmentHistoryCompareTool: AgentTool {
    public let service: EnvironmentHistoryService
    public var name: String { "environment_history_compare" }
    public var description: String { "Compare deterministic statistics from sparse environment snapshots Connor actually recorded for two to four explicitly named places. Does not backfill gaps, infer causes, or infer user behavior." }
    public var permission: AgentPermissionCapability { .readSession }
    public var inputSchema: AgentToolInputSchema {
        .closedObject(properties: [
            "places": .array(items: .string(description: "Explicit place name."), description: "Two to four explicit place names."),
            "start": .string(description: "Inclusive ISO-8601 start timestamp."),
            "end": .string(description: "Inclusive ISO-8601 end timestamp."),
            "categories": EnvironmentHistoryToolSupport.categorySchema
        ], required: ["places", "start", "end", "categories"])
    }

    public init(service: EnvironmentHistoryService) { self.service = service }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let places = (arguments.array("places") ?? []).compactMap(\.stringValue).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard (2...4).contains(places.count) else { throw AgentToolError.invalidArguments("places must contain two to four explicit place names") }
        guard let start = try arguments.iso8601Date("start"), let end = try arguments.iso8601Date("end"), start <= end else {
            throw AgentToolError.invalidArguments("start and end must be an ordered ISO-8601 range")
        }
        let categories = Set((arguments.array("categories") ?? []).compactMap(\.stringValue).compactMap(EnvironmentHistoryCategory.init(rawValue:)))
        guard !categories.isEmpty else { throw AgentToolError.invalidArguments("categories must not be empty") }
        var summaries: [EnvironmentHistoryToolSummary] = []
        for place in places {
            guard let result = try await service.query(placeName: place, startDate: start, endDate: end, categories: categories) else {
                throw AgentToolError.invalidArguments("No recorded coarse environment region matches \(place)")
            }
            summaries.append(EnvironmentHistoryToolSupport.summary(place: place, result: result))
        }
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Compared coarse historical environment evidence using deterministic statistics; no causal conclusion was generated.",
            contentJSON: try EnvironmentHistoryToolSupport.encode(summaries)
        )
    }
}

public extension AgentToolRegistry {
    mutating func registerEnvironmentHistoryTools(service: EnvironmentHistoryService) {
        register(EnvironmentHistoryCoverageTool(service: service))
        register(EnvironmentHistoryQueryTool(service: service))
        register(EnvironmentHistoryCompareTool(service: service))
    }
}
