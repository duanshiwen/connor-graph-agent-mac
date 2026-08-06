import Foundation
import Testing
import ConnorGraphAppSupport

// 这些测试共享 L1ExtractionEligibility 单例状态，必须串行执行，避免相互干扰。
@Suite("Device Sync Policy Tests", .serialized)
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

    @Test func l1EligibilityFallsBackLocallyWhenBackendUnreachable() {
        let now = Date()
        L1ExtractionEligibility.shared.enableLocalFallback()
        #expect(L1ExtractionEligibility.shared.canRun(now: now))
        // 后端恢复并授予租约后，回退模式立即失效，恢复原有租约语义。
        L1ExtractionEligibility.shared.update(granted: true, expiresAt: now.addingTimeInterval(10))
        #expect(L1ExtractionEligibility.shared.canRun(now: now))
        #expect(!L1ExtractionEligibility.shared.canRun(now: now.addingTimeInterval(11)))
        L1ExtractionEligibility.shared.update(granted: false, expiresAt: nil)
    }

    @Test func l1EligibilityBackendDenialDisablesLocalFallback() {
        // 后端在线但租约判给其他设备时，本机不得自行提取（保持多设备互斥语义）。
        L1ExtractionEligibility.shared.enableLocalFallback()
        L1ExtractionEligibility.shared.update(granted: false, expiresAt: nil)
        #expect(!L1ExtractionEligibility.shared.canRun())
    }

    @Test func l1EligibilityCanBeExplicitlyDisabled() {
        L1ExtractionEligibility.shared.enableLocalFallback()
        #expect(L1ExtractionEligibility.shared.canRun())
        L1ExtractionEligibility.shared.disable()
        #expect(!L1ExtractionEligibility.shared.canRun())
    }

    @Test func syncResultOnlyRefreshesChangedSurfaces() {
        let uploadOnly = AppAccountDataSyncResult(pushedChangeCount: 3)
        #expect(!uploadOnly.sessionsChanged)
        #expect(!uploadOnly.settingsChanged)

        let remoteChanges = AppAccountDataSyncResult(appliedSessionChangeCount: 2, appliedSettingsChangeCount: 1)
        #expect(remoteChanges.sessionsChanged)
        #expect(remoteChanges.settingsChanged)
    }
}
