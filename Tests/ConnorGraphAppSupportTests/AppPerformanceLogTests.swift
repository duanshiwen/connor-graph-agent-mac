import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("App Performance Log Tests")
struct AppPerformanceLogTests {
    @Test func chatTurnLoggerUsesStableSubsystemAndCategory() {
        #expect(AppPerformanceLog.subsystem == "ConnorGraphAgentMac")
        #expect(AppPerformanceLog.chatTurnCategory == "ChatTurnPerformance")
    }

    @Test func measuredDurationReportsElapsedMilliseconds() async throws {
        let result = await AppPerformanceLog.measure {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        #expect(result.duration.milliseconds >= 0)
    }
}
