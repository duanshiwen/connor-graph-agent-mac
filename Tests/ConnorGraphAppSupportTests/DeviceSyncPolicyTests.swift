import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Device Sync Policy Tests")
struct DeviceSyncPolicyTests {
    @Test func excludesRemoteAndMacLocalCollections() {
        for collection in ["mail", "calendar_events", "rss_feeds", "scheduled_tasks", "event_driven_tasks"] {
            #expect(!ConnorSyncChange.isSyncable(collection: collection))
        }
        for collection in ["settings", "sessions", "session_states", "session_details", "notes", "tasks", "memory_l1"] {
            #expect(ConnorSyncChange.isSyncable(collection: collection))
        }
    }

    @Test func l1EligibilityExpiresWithLease() {
        let now = Date()
        L1ExtractionEligibility.shared.update(granted: true, expiresAt: now.addingTimeInterval(10))
        #expect(L1ExtractionEligibility.shared.canRun(now: now))
        #expect(!L1ExtractionEligibility.shared.canRun(now: now.addingTimeInterval(11)))
        L1ExtractionEligibility.shared.update(granted: false, expiresAt: nil)
    }
}
