import Foundation
import Testing
import ConnorGraphAgent
@testable import ConnorGraphAppSupport

private actor OpenMeteoLoaderFixture {
    private(set) var callCount = 0
    var shouldFail = false

    func load(_ request: URLRequest) throws -> Data {
        callCount += 1
        if shouldFail { throw URLError(.cannotConnectToHost) }
        return Data(Self.responseJSON.utf8)
    }

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    private static let responseJSON = #"""
    {
      "timezone": "Asia/Shanghai",
      "current": {
        "time": "2026-07-24T10:00",
        "temperature_2m": 31.2,
        "apparent_temperature": 34.8,
        "relative_humidity_2m": 67,
        "precipitation": 0.0,
        "weather_code": 1,
        "wind_speed_10m": 8.5
      },
      "hourly": {
        "time": ["2026-07-24T10:00", "2026-07-24T11:00"],
        "temperature_2m": [31.2, 32.0],
        "precipitation_probability": [10, 20],
        "weather_code": [1, 2]
      }
    }
    """#
}

@Test func openMeteoUsesFixedStructuredEndpointAndCachesFreshWeather() async throws {
    let loader = OpenMeteoLoaderFixture()
    let fixedNow = Date(timeIntervalSince1970: 1_790_000_000)
    let provider = OpenMeteoWeatherProvider(
        cacheLifetime: 15 * 60,
        now: { fixedNow },
        dataLoader: { request in try await loader.load(request) }
    )
    let request = EnvironmentWeatherRequest(latitude: 30.25, longitude: 120.17)

    let first = await provider.weather(for: request)
    let second = await provider.weather(for: request)

    #expect(await loader.callCount == 1)
    #expect(first == second)
    #expect(first.status == .available)
    #expect(first.source == "Open-Meteo")
    #expect(first.condition == "少云")
    #expect(first.temperatureCelsius == 31.2)
    #expect(first.hourlyForecast.count == 2)
}

@Test func openMeteoFallsBackToStaleCacheWhenRefreshFails() async throws {
    let loader = OpenMeteoLoaderFixture()
    let fixedNow = Date(timeIntervalSince1970: 1_790_000_000)
    let provider = OpenMeteoWeatherProvider(
        now: { fixedNow },
        dataLoader: { request in try await loader.load(request) }
    )
    let normalRequest = EnvironmentWeatherRequest(latitude: 30.25, longitude: 120.17)
    _ = await provider.weather(for: normalRequest)
    await loader.setShouldFail(true)

    let stale = await provider.weather(for: EnvironmentWeatherRequest(
        latitude: 30.25,
        longitude: 120.17,
        refresh: true
    ))

    #expect(await loader.callCount == 2)
    #expect(stale.status == .stale)
    #expect(stale.temperatureCelsius == 31.2)
    #expect(stale.message?.contains("缓存") == true)
}
