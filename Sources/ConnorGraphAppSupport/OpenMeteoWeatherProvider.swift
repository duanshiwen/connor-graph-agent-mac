import Foundation
import ConnorGraphAgent

public struct EnvironmentWeatherRequest: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var refresh: Bool

    public init(latitude: Double, longitude: Double, refresh: Bool = false) {
        self.latitude = latitude
        self.longitude = longitude
        self.refresh = refresh
    }
}

public protocol EnvironmentWeatherProviding: Sendable {
    func weather(for request: EnvironmentWeatherRequest) async -> AgentEnvironmentWeather
}

public actor OpenMeteoWeatherProvider: EnvironmentWeatherProviding {
    public typealias DataLoader = @Sendable (URLRequest) async throws -> Data

    private struct CacheEntry: Sendable {
        var weather: AgentEnvironmentWeather
        var expiresAt: Date
    }

    private let endpoint: URL
    private let cacheLifetime: TimeInterval
    private let requestTimeout: TimeInterval
    private let now: @Sendable () -> Date
    private let dataLoader: DataLoader
    private var cache: [String: CacheEntry] = [:]

    public init(
        endpoint: URL = URL(string: "https://api.open-meteo.com/v1/forecast")!,
        cacheLifetime: TimeInterval = 15 * 60,
        requestTimeout: TimeInterval = 3,
        now: @escaping @Sendable () -> Date = Date.init,
        dataLoader: @escaping DataLoader = OpenMeteoWeatherProvider.liveDataLoader
    ) {
        self.endpoint = endpoint
        self.cacheLifetime = max(60, cacheLifetime)
        self.requestTimeout = max(1, requestTimeout)
        self.now = now
        self.dataLoader = dataLoader
    }

    public func weather(for request: EnvironmentWeatherRequest) async -> AgentEnvironmentWeather {
        let fetchedAt = now()
        let key = cacheKey(latitude: request.latitude, longitude: request.longitude)
        if !request.refresh, let cached = cache[key], cached.expiresAt > fetchedAt {
            return cached.weather
        }

        do {
            let url = try requestURL(latitude: request.latitude, longitude: request.longitude)
            var urlRequest = URLRequest(url: url)
            urlRequest.timeoutInterval = requestTimeout
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            urlRequest.setValue("ConnorGraphAgent/1.0", forHTTPHeaderField: "User-Agent")
            let data = try await dataLoader(urlRequest)
            let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let expiresAt = fetchedAt.addingTimeInterval(cacheLifetime)
            let weather = response.agentWeather(fetchedAt: fetchedAt, expiresAt: expiresAt)
            cache[key] = CacheEntry(weather: weather, expiresAt: expiresAt)
            return weather
        } catch {
            if var cached = cache[key]?.weather {
                cached.status = .stale
                cached.message = "天气服务暂时不可用，当前返回最近一次缓存。"
                return cached
            }
            return AgentEnvironmentWeather(
                status: error is CancellationError ? .timedOut : .unavailable,
                source: "Open-Meteo",
                sourceURL: "https://open-meteo.com/",
                updatedAt: fetchedAt,
                message: "天气服务暂时不可用。"
            )
        }
    }

    public static func liveDataLoader(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw OpenMeteoError.invalidResponse
        }
        return data
    }

    private func requestURL(latitude: Double, longitude: Double) throws -> URL {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw OpenMeteoError.invalidCoordinate
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.5f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.5f", longitude)),
            URLQueryItem(name: "current", value: [
                "temperature_2m",
                "apparent_temperature",
                "relative_humidity_2m",
                "precipitation",
                "weather_code",
                "wind_speed_10m"
            ].joined(separator: ",")),
            URLQueryItem(name: "hourly", value: [
                "temperature_2m",
                "precipitation_probability",
                "weather_code"
            ].joined(separator: ",")),
            URLQueryItem(name: "forecast_hours", value: "12"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else { throw OpenMeteoError.invalidURL }
        return url
    }

    private func cacheKey(latitude: Double, longitude: Double) -> String {
        "\((latitude * 10).rounded() / 10),\((longitude * 10).rounded() / 10)"
    }
}

private enum OpenMeteoError: Error {
    case invalidCoordinate
    case invalidURL
    case invalidResponse
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        var time: String
        var temperature_2m: Double?
        var apparent_temperature: Double?
        var relative_humidity_2m: Int?
        var precipitation: Double?
        var weather_code: Int?
        var wind_speed_10m: Double?
    }

    struct Hourly: Decodable {
        var time: [String]
        var temperature_2m: [Double?]?
        var precipitation_probability: [Int?]?
        var weather_code: [Int?]?
    }

    var timezone: String?
    var current: Current
    var hourly: Hourly?

    func agentWeather(fetchedAt: Date, expiresAt: Date) -> AgentEnvironmentWeather {
        let hours = hourly?.time.enumerated().map { index, time in
            AgentEnvironmentHourlyWeather(
                localTime: time,
                temperatureCelsius: hourly?.temperature_2m?[safe: index] ?? nil,
                precipitationProbabilityPercent: hourly?.precipitation_probability?[safe: index] ?? nil,
                weatherCode: hourly?.weather_code?[safe: index] ?? nil
            )
        } ?? []
        return AgentEnvironmentWeather(
            status: .available,
            condition: Self.condition(for: current.weather_code),
            temperatureCelsius: current.temperature_2m,
            apparentTemperatureCelsius: current.apparent_temperature,
            relativeHumidityPercent: current.relative_humidity_2m,
            precipitationMillimeters: current.precipitation,
            windSpeedKilometersPerHour: current.wind_speed_10m,
            hourlyForecast: Array(hours.prefix(12)),
            source: "Open-Meteo",
            sourceURL: "https://open-meteo.com/",
            updatedAt: fetchedAt,
            expiresAt: expiresAt
        )
    }

    private static func condition(for code: Int?) -> String? {
        guard let code else { return nil }
        switch code {
        case 0: return "晴朗"
        case 1, 2: return "少云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51, 53, 55, 56, 57: return "毛毛雨"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "雨"
        case 71, 73, 75, 77, 85, 86: return "雪"
        case 95, 96, 99: return "雷暴"
        default: return "未知天气"
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
