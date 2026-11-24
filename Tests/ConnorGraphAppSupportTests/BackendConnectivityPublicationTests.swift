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
    @Test func realTrafficPostponesProbesAndFailuresBackOff() {
        let now = Date(timeIntervalSince1970: 1_000)
        var policy = BackendHealthProbePolicy()
        #expect(policy.delay(at: now) == 0)
        policy.succeeded(at: now)
        #expect(policy.delay(at: now) == 60)
        policy.succeeded(at: now.addingTimeInterval(50))
        #expect(policy.delay(at: now.addingTimeInterval(60)) == 50)
        for expected in [10.0, 20, 40, 80, 120, 120] {
            policy.failed(at: now)
            #expect(policy.delay(at: now) == expected)
        }
        policy.succeeded(at: now)
        policy.failed(at: now)
        #expect(policy.delay(at: now) == 10)
    }

}
