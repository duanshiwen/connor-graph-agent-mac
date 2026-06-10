import Foundation
import Testing
import ConnorGraphMemory

@Test func memoryPromotionDismissMarksEntryDismissedWithoutStoreCompatibilityLayer() throws {
    let service = MemoryPromotionService()
    let entry = ObserveLogEntry(id: "obs-dismiss", kind: .candidateFact, source: .agent, content: "Dismiss me")

    let dismissed = service.dismiss(entry)

    #expect(dismissed.status == .dismissed)
    #expect(dismissed.id == entry.id)
}

@Test func memoryPromotionPinExtendsExpiryWithoutStoreCompatibilityLayer() throws {
    let service = MemoryPromotionService()
    let now = Date(timeIntervalSince1970: 1_000)
    let entry = ObserveLogEntry(id: "obs-pin", kind: .candidateFact, source: .agent, content: "Pin me", expiresAt: now)

    let pinned = service.pin(entry, at: now, additionalDays: 1)

    #expect(pinned.status == entry.status)
    #expect(pinned.expiresAt == Date(timeIntervalSince1970: 1_000 + 24 * 60 * 60))
}
