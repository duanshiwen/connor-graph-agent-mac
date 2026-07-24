import Foundation
import ConnorGraphAgent

public enum EnvironmentHistoryCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case weather
    case airQuality = "air_quality"
}

public struct ResolvedEnvironmentRegion: Sendable, Equatable {
    public var region: AgentEnvironmentRegion
    public var displayName: String
    public var locality: String?
    public var administrativeArea: String?
    public var countryCode: String?
    public var timeZoneIdentifier: String
}

public struct EnvironmentHistoryFetchRequest: Sendable, Equatable {
    public var region: ResolvedEnvironmentRegion
    public var startDate: Date
    public var endDate: Date

    public init(region: ResolvedEnvironmentRegion, startDate: Date, endDate: Date) {
        self.region = region
        self.startDate = startDate
        self.endDate = endDate
    }
}

public struct EnvironmentHistoryWeatherSample: Sendable, Equatable {
    public var observedAt: Date
    public var temperatureCelsius: Double?
    public var apparentTemperatureCelsius: Double?
    public var relativeHumidityPercent: Int?
    public var precipitationMillimeters: Double?
    public var weatherCode: Int?
    public var windSpeedKilometersPerHour: Double?
}

public struct EnvironmentHistoryAirQualitySample: Sendable, Equatable {
    public var observedAt: Date
    public var europeanAQI: Int?
    public var usAQI: Int?
    public var pm10: Double?
    public var pm2_5: Double?
    public var nitrogenDioxide: Double?
    public var ozone: Double?
}

public protocol EnvironmentRegionResolving: Sendable {
    func resolve(placeName: String) async throws -> ResolvedEnvironmentRegion?
}

public protocol EnvironmentHistoryProviding: Sendable {
    func weather(for request: EnvironmentHistoryFetchRequest) async throws -> [EnvironmentHistoryWeatherSample]
    func airQuality(for request: EnvironmentHistoryFetchRequest) async throws -> [EnvironmentHistoryAirQualitySample]
}

public struct OpenMeteoEnvironmentHistoryProvider: EnvironmentRegionResolving, EnvironmentHistoryProviding, Sendable {
    public typealias DataLoader = @Sendable (URLRequest) async throws -> Data

    private let geocodingEndpoint: URL
    private let weatherEndpoint: URL
    private let airQualityEndpoint: URL
    private let requestTimeout: TimeInterval
    private let dataLoader: DataLoader

    public init(
        geocodingEndpoint: URL = URL(string: "https://geocoding-api.open-meteo.com/v1/search")!,
        weatherEndpoint: URL = URL(string: "https://archive-api.open-meteo.com/v1/archive")!,
        airQualityEndpoint: URL = URL(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!,
        requestTimeout: TimeInterval = 8,
        dataLoader: @escaping DataLoader = OpenMeteoWeatherProvider.liveDataLoader
    ) {
        self.geocodingEndpoint = geocodingEndpoint
        self.weatherEndpoint = weatherEndpoint
        self.airQualityEndpoint = airQualityEndpoint
        self.requestTimeout = max(1, requestTimeout)
        self.dataLoader = dataLoader
    }

    public func resolve(placeName: String) async throws -> ResolvedEnvironmentRegion? {
        let normalized = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else { return nil }
        var components = URLComponents(url: geocodingEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "name", value: normalized),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "format", value: "json")
        ]
        let data = try await load(components)
        guard let match = try JSONDecoder().decode(GeocodingResponse.self, from: data).results?.first,
              let region = AgentEnvironmentRegion.containing(latitude: match.latitude, longitude: match.longitude) else { return nil }
        return ResolvedEnvironmentRegion(
            region: region,
            displayName: [match.name, match.admin1, match.country].compactMap { $0 }.joined(separator: ", "),
            locality: match.name,
            administrativeArea: match.admin1,
            countryCode: match.country_code,
            timeZoneIdentifier: match.timezone ?? "UTC"
        )
    }

    public func weather(for request: EnvironmentHistoryFetchRequest) async throws -> [EnvironmentHistoryWeatherSample] {
        var components = baseHistoryComponents(endpoint: weatherEndpoint, request: request)
        components.queryItems?.append(URLQueryItem(name: "hourly", value: [
            "temperature_2m", "apparent_temperature", "relative_humidity_2m", "precipitation",
            "weather_code", "wind_speed_10m"
        ].joined(separator: ",")))
        let data = try await load(components)
        let response = try JSONDecoder().decode(WeatherResponse.self, from: data)
        return zipSamples(times: response.hourly.time, timeZoneIdentifier: response.timezone ?? request.region.timeZoneIdentifier) { index, date in
            EnvironmentHistoryWeatherSample(
                observedAt: date,
                temperatureCelsius: response.hourly.temperature_2m?[safe: index] ?? nil,
                apparentTemperatureCelsius: response.hourly.apparent_temperature?[safe: index] ?? nil,
                relativeHumidityPercent: response.hourly.relative_humidity_2m?[safe: index] ?? nil,
                precipitationMillimeters: response.hourly.precipitation?[safe: index] ?? nil,
                weatherCode: response.hourly.weather_code?[safe: index] ?? nil,
                windSpeedKilometersPerHour: response.hourly.wind_speed_10m?[safe: index] ?? nil
            )
        }
    }

    public func airQuality(for request: EnvironmentHistoryFetchRequest) async throws -> [EnvironmentHistoryAirQualitySample] {
        var components = baseHistoryComponents(endpoint: airQualityEndpoint, request: request)
        components.queryItems?.append(URLQueryItem(name: "hourly", value: [
            "european_aqi", "us_aqi", "pm10", "pm2_5", "nitrogen_dioxide", "ozone"
        ].joined(separator: ",")))
        let data = try await load(components)
        let response = try JSONDecoder().decode(AirQualityResponse.self, from: data)
        return zipSamples(times: response.hourly.time, timeZoneIdentifier: response.timezone ?? request.region.timeZoneIdentifier) { index, date in
            EnvironmentHistoryAirQualitySample(
                observedAt: date,
                europeanAQI: response.hourly.european_aqi?[safe: index] ?? nil,
                usAQI: response.hourly.us_aqi?[safe: index] ?? nil,
                pm10: response.hourly.pm10?[safe: index] ?? nil,
                pm2_5: response.hourly.pm2_5?[safe: index] ?? nil,
                nitrogenDioxide: response.hourly.nitrogen_dioxide?[safe: index] ?? nil,
                ozone: response.hourly.ozone?[safe: index] ?? nil
            )
        }
    }

    private func baseHistoryComponents(endpoint: URL, request: EnvironmentHistoryFetchRequest) -> URLComponents {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: request.region.timeZoneIdentifier) ?? .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", request.region.region.centerLatitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", request.region.region.centerLongitude)),
            URLQueryItem(name: "start_date", value: formatter.string(from: request.startDate)),
            URLQueryItem(name: "end_date", value: formatter.string(from: request.endDate)),
            URLQueryItem(name: "timezone", value: request.region.timeZoneIdentifier)
        ]
        return components
    }

    private func load(_ components: URLComponents?) async throws -> Data {
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ConnorGraphAgent/1.0", forHTTPHeaderField: "User-Agent")
        return try await dataLoader(request)
    }

    private func zipSamples<T>(
        times: [String],
        timeZoneIdentifier: String,
        transform: (Int, Date) -> T
    ) -> [T] {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return [] }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return times.enumerated().compactMap { index, value in
            formatter.date(from: value).map { transform(index, $0) }
        }
    }
}

private struct GeocodingResponse: Decodable {
    struct Match: Decodable {
        var name: String
        var latitude: Double
        var longitude: Double
        var country_code: String?
        var country: String?
        var admin1: String?
        var timezone: String?
    }
    var results: [Match]?
}

private struct WeatherResponse: Decodable {
    struct Hourly: Decodable {
        var time: [String]
        var temperature_2m: [Double?]?
        var apparent_temperature: [Double?]?
        var relative_humidity_2m: [Int?]?
        var precipitation: [Double?]?
        var weather_code: [Int?]?
        var wind_speed_10m: [Double?]?
    }
    var timezone: String?
    var hourly: Hourly
}

private struct AirQualityResponse: Decodable {
    struct Hourly: Decodable {
        var time: [String]
        var european_aqi: [Int?]?
        var us_aqi: [Int?]?
        var pm10: [Double?]?
        var pm2_5: [Double?]?
        var nitrogen_dioxide: [Double?]?
        var ozone: [Double?]?
    }
    var timezone: String?
    var hourly: Hourly
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
