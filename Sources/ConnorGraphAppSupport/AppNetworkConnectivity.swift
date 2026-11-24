import Foundation
import Network
import Combine

@MainActor
public final class AppNetworkConnectivity: ObservableObject {
    public static let shared = AppNetworkConnectivity()

    @Published public private(set) var isConnected: Bool

    private let monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.connorgraph.network-connectivity")

    public init(initiallyConnected: Bool = true, startMonitoring: Bool = true) {
        isConnected = initiallyConnected
        guard startMonitoring else {
            monitor = nil
            return
        }

        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isConnected != isConnected else { return }
                self.isConnected = isConnected
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor?.cancel()
    }
}

public enum AppBackendConnectionState: Sendable, Equatable {
    case unknown
    case reachable
    case unreachable
}

public enum AppBackendConnectionFailure {
    public static func isUnreachable(_ error: Error) -> Bool {
        let urlError: URLError
        if let error = error as? URLError {
            urlError = error
        } else {
            let nsError = error as NSError
            guard nsError.domain == NSURLErrorDomain else { return false }
            urlError = URLError(URLError.Code(rawValue: nsError.code))
        }

        return switch urlError.code {
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut,
             .networkConnectionLost, .notConnectedToInternet, .internationalRoamingOff,
             .callIsActive, .dataNotAllowed, .secureConnectionFailed:
            true
        default:
            false
        }
    }
}

/// Successful real requests postpone health checks; failures back off instead
/// of issuing a request every ten seconds indefinitely.
struct BackendHealthProbePolicy {
    private(set) var nextProbeAt = Date.distantPast
    private(set) var consecutiveFailures = 0

    mutating func succeeded(at now: Date) {
        consecutiveFailures = 0
        nextProbeAt = now.addingTimeInterval(60)
    }

    mutating func failed(at now: Date) {
        consecutiveFailures = min(consecutiveFailures + 1, 5)
        nextProbeAt = now.addingTimeInterval(min(10 * pow(2, Double(consecutiveFailures - 1)), 120))
    }

    func delay(at now: Date) -> TimeInterval { max(0, nextProbeAt.timeIntervalSince(now)) }
}

@MainActor
public final class AppBackendConnectivity: ObservableObject {
    public static let shared = AppBackendConnectivity()

    @Published public private(set) var state: AppBackendConnectionState = .unknown

    private var baseURL: URL?
    private var monitoringTask: Task<Void, Never>?
    private var configurationGeneration = 0
    private var probePolicy = BackendHealthProbePolicy()
    private var networkSubscription: AnyCancellable?

    deinit { monitoringTask?.cancel() }

    public var baseURLString: String? { baseURL?.absoluteString }
    public var isReachable: Bool { state != .unreachable }

    public func configure(baseURL: URL) {
        guard self.baseURL != baseURL || monitoringTask == nil else { return }
        monitoringTask?.cancel()
        configurationGeneration += 1
        self.baseURL = baseURL
        probePolicy = BackendHealthProbePolicy()
        if state != .unknown { state = .unknown }
        if networkSubscription == nil {
            networkSubscription = AppNetworkConnectivity.shared.$isConnected
                .dropFirst().removeDuplicates().sink { [weak self] connected in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.monitoringTask?.cancel()
                        self.monitoringTask = nil
                        if connected, let baseURL = self.baseURL { self.configure(baseURL: baseURL) }
                    }
                }
        }
        guard AppNetworkConnectivity.shared.isConnected else { return }
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.probePolicy.delay(at: Date()) else { return }
                if delay <= 0 { await self?.probe() }
                guard !Task.isCancelled, let nextDelay = self?.probePolicy.delay(at: Date()) else { return }
                let sleep = max(1, nextDelay)
                // Release the owner before sleeping so monitoring cannot keep it alive.
                do { try await Task.sleep(for: .seconds(sleep), tolerance: .seconds(min(sleep * 0.1, 5))) }
                catch { return }
            }
        }
    }

    public func recordReachable() {
        probePolicy.succeeded(at: Date())
        if state != .reachable { state = .reachable }
    }

    public func recordFailure(_ error: Error) {
        if AppBackendConnectionFailure.isUnreachable(error) {
            probePolicy.failed(at: Date())
            if state != .unreachable { state = .unreachable }
        }
    }

    private func probe() async {
        guard !Task.isCancelled, let baseURL else { return }
        let generation = configurationGeneration
        let healthURL = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, generation == configurationGeneration else { return }
            if response is HTTPURLResponse { recordReachable() }
        } catch {
            guard !Task.isCancelled, generation == configurationGeneration else { return }
            recordFailure(error)
            if probePolicy.delay(at: Date()) <= 0 { probePolicy.failed(at: Date()) }
        }
    }
}

public struct BackendConnectivityTrackingTransport: ConnorBackendHTTPTransport {
    private let base: any ConnorBackendHTTPTransport
    private let connectivity: AppBackendConnectivity

    @MainActor public init(
        base: any ConnorBackendHTTPTransport = URLSession.shared,
        connectivity: AppBackendConnectivity = .shared
    ) {
        self.base = base
        self.connectivity = connectivity
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let result = try await base.data(for: request)
            await connectivity.recordReachable()
            return result
        } catch {
            await connectivity.recordFailure(error)
            throw error
        }
    }
}
