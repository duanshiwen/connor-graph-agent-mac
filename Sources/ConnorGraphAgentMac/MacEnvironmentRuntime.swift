import CoreLocation
import Foundation
import ConnorGraphAgent
import ConnorGraphAppSupport

struct MacEnvironmentLocationReading: Sendable, Equatable {
    var status: AgentEnvironmentDataStatus
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracyMeters: Double?
    var locality: String?
    var administrativeArea: String?
    var country: String?
    var timeZoneIdentifier: String?
    var capturedAt: Date?
    var message: String?
}

@MainActor
final class MacCurrentLocationService: NSObject, @preconcurrency CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var continuations: [CheckedContinuation<MacEnvironmentLocationReading, Never>] = []
    private var timeoutTask: Task<Void, Never>?
    private var cachedReading: MacEnvironmentLocationReading?
    private var requestIsActive = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func currentLocation() async -> MacEnvironmentLocationReading {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
            guard !requestIsActive else { return }
            requestIsActive = true
            beginRequest()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard requestIsActive else { return }
            manager.requestLocation()
            scheduleTimeout()
        case .denied, .restricted:
            finish(MacEnvironmentLocationReading(
                status: .denied,
                message: "定位权限未开启。"
            ))
        case .notDetermined:
            break
        @unknown default:
            finish(MacEnvironmentLocationReading(
                status: .unavailable,
                message: "无法确定定位权限状态。"
            ))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last(where: { $0.horizontalAccuracy >= 0 }) else {
            finish(fallbackReading(status: .unavailable, message: "暂时无法读取当前位置。"))
            return
        }
        let age = abs(location.timestamp.timeIntervalSinceNow)
        guard age <= 10 * 60 else {
            finish(fallbackReading(status: .stale, message: "系统返回的位置已经过期。"))
            return
        }
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let placemark = placemarks?.first
                let reading = MacEnvironmentLocationReading(
                    status: .available,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    horizontalAccuracyMeters: location.horizontalAccuracy,
                    locality: placemark?.locality ?? placemark?.subAdministrativeArea,
                    administrativeArea: placemark?.administrativeArea,
                    country: placemark?.country,
                    timeZoneIdentifier: placemark?.timeZone?.identifier,
                    capturedAt: location.timestamp
                )
                self.cachedReading = reading
                self.finish(reading)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let status: AgentEnvironmentDataStatus = (error as? CLError)?.code == .denied ? .denied : .unavailable
        finish(fallbackReading(status: status, message: status == .denied ? "定位权限未开启。" : "暂时无法读取当前位置。"))
    }

    private func beginRequest() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            scheduleTimeout()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
            scheduleTimeout()
        case .denied, .restricted:
            finish(MacEnvironmentLocationReading(status: .denied, message: "定位权限未开启。"))
        @unknown default:
            finish(MacEnvironmentLocationReading(status: .unavailable, message: "无法确定定位权限状态。"))
        }
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.requestIsActive else { return }
                self.finish(self.fallbackReading(status: .timedOut, message: "获取当前位置超时。"))
            }
        }
    }

    private func fallbackReading(status: AgentEnvironmentDataStatus, message: String) -> MacEnvironmentLocationReading {
        guard var cached = cachedReading,
              let capturedAt = cached.capturedAt,
              Date().timeIntervalSince(capturedAt) <= 30 * 60 else {
            return MacEnvironmentLocationReading(status: status, message: message)
        }
        cached.status = .stale
        cached.message = "\(message) 当前使用最近一次位置。"
        return cached
    }

    private func finish(_ reading: MacEnvironmentLocationReading) {
        guard requestIsActive else { return }
        requestIsActive = false
        timeoutTask?.cancel()
        timeoutTask = nil
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: reading) }
    }
}

actor MacAgentEnvironmentProvider: AgentEnvironmentProviding {
    private let locationService: MacCurrentLocationService
    private let weatherProvider: any EnvironmentWeatherProviding
    private let persistence: (any EnvironmentSnapshotPersisting)?
    private let now: @Sendable () -> Date

    init(
        locationService: MacCurrentLocationService,
        weatherProvider: any EnvironmentWeatherProviding,
        persistence: (any EnvironmentSnapshotPersisting)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.locationService = locationService
        self.weatherProvider = weatherProvider
        self.persistence = persistence
        self.now = now
    }

    func snapshot(for request: AgentEnvironmentRequest) async -> AgentEnvironmentSnapshot {
        let location = await locationService.currentLocation()
        let capturedAt = now()
        let timeZone = location.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        let region: AgentEnvironmentRegion?
        if let latitude = location.latitude, let longitude = location.longitude {
            region = AgentEnvironmentRegion.containing(latitude: latitude, longitude: longitude)
        } else {
            region = nil
        }
        let weather: AgentEnvironmentWeather
        if let region {
            weather = await weatherProvider.weather(for: EnvironmentWeatherRequest(
                latitude: region.centerLatitude,
                longitude: region.centerLongitude,
                refresh: request.refresh
            ))
        } else {
            weather = AgentEnvironmentWeather(
                status: location.status == .timedOut ? .timedOut : .unavailable,
                source: "Open-Meteo",
                sourceURL: "https://open-meteo.com/",
                updatedAt: capturedAt,
                message: "没有可用于天气查询的位置。"
            )
        }
        let localTime = Self.localTime(at: capturedAt, timeZone: timeZone)
        var warnings: [String] = []
        if location.status != .available { warnings.append(location.message ?? "当前位置不可用。") }
        if weather.status != .available { warnings.append(weather.message ?? "当前天气不可用。") }
        let snapshot = AgentEnvironmentSnapshot(
            capturedAt: capturedAt,
            location: AgentEnvironmentLocation(
                status: location.status,
                locality: location.locality,
                administrativeArea: location.administrativeArea,
                country: location.country,
                gridCellID: region?.gridCellID,
                latitude: region?.centerLatitude,
                longitude: region?.centerLongitude,
                horizontalAccuracyMeters: nil,
                capturedAt: location.capturedAt,
                message: location.message
            ),
            localTime: localTime,
            weather: weather,
            warnings: warnings
        )
        if let persistence {
            Task { await persistence.record(snapshot) }
        }
        return snapshot
    }

    private static func localTime(at date: Date, timeZone: TimeZone) -> AgentEnvironmentLocalTime {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let hour = Calendar(identifier: .gregorian).dateComponents(in: timeZone, from: date).hour ?? 0
        let period: String
        switch hour {
        case 5..<12: period = "morning"
        case 12..<18: period = "afternoon"
        case 18..<22: period = "evening"
        default: period = "night"
        }
        return AgentEnvironmentLocalTime(
            timeZoneIdentifier: timeZone.identifier,
            localDateTime: formatter.string(from: date),
            dayPeriod: period
        )
    }
}
