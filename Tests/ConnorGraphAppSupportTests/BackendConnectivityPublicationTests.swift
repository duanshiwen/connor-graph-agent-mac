import Combine
import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Backend connectivity publications")
struct BackendConnectivityPublicationTests {
    @MainActor
    @Test func repeatedTrafficOnlyPublishesConnectivityTransitions() {
        let connectivity = AppBackendConnectivity()
        var states: [AppBackendConnectionState] = []
        let subscription = connectivity.$state.sink { states.append($0) }
        connectivity.recordReachable()
        connectivity.recordReachable()
        connectivity.recordFailure(URLError(.cancelled))
        connectivity.recordFailure(URLError(.notConnectedToInternet))
        connectivity.recordFailure(URLError(.notConnectedToInternet))
        connectivity.recordReachable()
        #expect(states == [.unknown, .reachable, .unreachable, .reachable])
        withExtendedLifetime(subscription) {}
    }
}
