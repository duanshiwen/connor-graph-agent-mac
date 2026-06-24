import Foundation
import Testing
import ConnorGraphCore

@Suite("Calendar Source Sync State Domain Tests")
struct CalendarSourceSyncStateDomainTests {
    @Test func accountSyncStateCodableRoundTripsCollectionCursorAndFailure() throws {
        let now = Date(timeIntervalSince1970: 1_782_278_400)
        let retry = now.addingTimeInterval(300)
        let state = CalendarAccountSyncState(
            accountID: CalendarAccountID(rawValue: "calendar-account-caldav"),
            sourceKind: .genericCalDAV,
            lastAttemptedSyncAt: now,
            lastSuccessfulSyncAt: now,
            failureCount: 2,
            nextRetryAt: retry,
            lastFailure: CalendarSyncFailureRecord(
                occurredAt: now,
                code: "http401",
                message: "Unauthorized",
                isCredentialRelated: true
            ),
            collectionStates: [
                CalendarCollectionSyncState(
                    collectionID: CalendarID(rawValue: "calendar-work"),
                    cursor: CalendarSourceSyncCursor(syncToken: "sync-123", etag: "etag-abc", lastSeenEventIDs: [CalendarEventID(rawValue: "event-1")]),
                    lastSuccessfulSyncAt: now,
                    eventCount: 42
                )
            ]
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CalendarAccountSyncState.self, from: data)

        #expect(decoded == state)
        #expect(decoded.collectionStates.first?.cursor.syncToken == "sync-123")
        #expect(decoded.lastFailure?.isCredentialRelated == true)
        #expect(decoded.nextRetryAt == retry)
    }

    @Test func backoffPolicyComputesBoundedRetryDelay() {
        let policy = CalendarSyncBackoffPolicy(initialDelaySeconds: 30, multiplier: 2, maxDelaySeconds: 600)

        #expect(policy.delaySeconds(failureCount: 0) == 0)
        #expect(policy.delaySeconds(failureCount: 1) == 30)
        #expect(policy.delaySeconds(failureCount: 3) == 120)
        #expect(policy.delaySeconds(failureCount: 10) == 600)
    }
}
