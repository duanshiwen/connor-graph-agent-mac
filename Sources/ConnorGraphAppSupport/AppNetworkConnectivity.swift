import Foundation
import Network

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
                self?.isConnected = isConnected
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

@MainActor
public final class AppBackendConnectivity: ObservableObject {
    public static let shared = AppBackendConnectivity()

    @Published public private(set) var state: AppBackendConnectionState = .unknown

    private var baseURL: URL?
    private var monitoringTask: Task<Void, Never>?

    public var isReachable: Bool { state != .unreachable }

    public func configure(baseURL: URL) {
        guard self.baseURL != baseURL || monitoringTask == nil else { return }
        monitoringTask?.cancel()
        self.baseURL = baseURL
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.probe()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    public func recordReachable() {
        state = .reachable
    }

    public func recordFailure(_ error: Error) {
        if AppBackendConnectionFailure.isUnreachable(error) {
            state = .unreachable
        }
    }

    private func probe() async {
        guard let baseURL else { return }
        var request = URLRequest(url: baseURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if response is HTTPURLResponse { recordReachable() }
        } catch {
            recordFailure(error)
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
