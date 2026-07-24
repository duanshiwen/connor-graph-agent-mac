import Foundation
import Testing
import ConnorGraphAgent
@testable import ConnorGraphAppSupport

private actor HistoryRequestRecorder {
    var urls: [URL] = []

    func load(_ request: URLRequest) throws -> Data {
        urls.append(request.url!)
        switch request.url?.host {
        case "geocoding.test":
            return Data(#"{"results":[{"name":"杭州","latitude":30.12345,"longitude":120.98765,"country_code":"CN","admin1":"浙江","timezone":"Asia/Shanghai"}]}"#.utf8)
        case "weather.test":
            return Data(#"{"timezone":"Asia/Shanghai","hourly":{"time":["2026-07-01T00:00"],"temperature_2m":[28.0],"apparent_temperature":[30.0],"relative_humidity_2m":[70],"precipitation":[0.2],"weather_code":[1],"wind_speed_10m":[8.0]}}"#.utf8)
        default:
            return Data(#"{"timezone":"Asia/Shanghai","hourly":{"time":["2026-07-01T00:00"],"european_aqi":[42],"us_aqi":[50],"pm10":[18.0],"pm2_5":[9.0],"nitrogen_dioxide":[12.0],"ozone":[70.0]}}"#.utf8)
        }
    }
}

@Test func historicalProviderUsesResolvedCoarseGridForStructuredEndpoints() async throws {
    let recorder = HistoryRequestRecorder()
    let provider = OpenMeteoEnvironmentHistoryProvider(
        geocodingEndpoint: URL(string: "https://geocoding.test/v1/search")!,
        weatherEndpoint: URL(string: "https://weather.test/v1/archive")!,
        airQualityEndpoint: URL(string: "https://air.test/v1/air-quality")!,
        dataLoader: { request in try await recorder.load(request) }
    )
    let region = try #require(try await provider.resolve(placeName: "杭州"))
    let request = EnvironmentHistoryFetchRequest(
        region: region,
        startDate: Date(timeIntervalSince1970: 1_783_017_600),
        endDate: Date(timeIntervalSince1970: 1_783_017_600)
    )
    let weather = try await provider.weather(for: request)
    let air = try await provider.airQuality(for: request)

    #expect(weather.first?.temperatureCelsius == 28)
    #expect(air.first?.europeanAQI == 42)
    let urls = await recorder.urls
    #expect(urls.count == 3)
    let historyURLs = urls.dropFirst().map(\.absoluteString).joined(separator: "\n")
    #expect(historyURLs.contains(String(format: "%.3f", region.region.centerLatitude)))
    #expect(historyURLs.contains(String(format: "%.3f", region.region.centerLongitude)))
    #expect(!historyURLs.contains("30.12345"))
    #expect(!historyURLs.contains("120.98765"))
}
