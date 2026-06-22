import Foundation
import Testing
import ConnorGraphCore

@Test func memoryOSStableKeyBuilderNormalizesEntityKeys() {
    let key = MemoryOSStableKeyBuilder.stableKey(type: "person", name: " Shiwen User ", scope: "personal")

    #expect(key == "personal:person:shiwen-user")
}

@Test func memoryOSDomainRoundTripsProvenanceObject() throws {
    let object = MemoryOSProvenanceObject(
        id: "prov-1",
        sourceType: .chatMessage,
        sourceID: "message-1",
        title: "User preference",
        content: "诗闻 prefers production-grade systems.",
        contentHash: "hash-1",
        occurredAt: Date(timeIntervalSince1970: 1_000),
        ingestedAt: Date(timeIntervalSince1970: 1_001),
        sessionID: "session-1",
        confidentiality: .personal,
        metadata: ["quality": "production"]
    )

    let data = try JSONEncoder().encode(object)
    let decoded = try JSONDecoder().decode(MemoryOSProvenanceObject.self, from: data)

    #expect(decoded == object)
}

@Test func memoryOSQueueItemCarriesProductionRecoveryFields() {
    let now = Date(timeIntervalSince1970: 2_000)
    let item = MemoryOSQueueItem(
        id: "queue-1",
        kind: "l2_processing",
        status: .leased,
        attemptCount: 2,
        maxAttempts: 5,
        nextRunAt: now,
        lockedAt: now,
        lockedBy: "worker-1",
        leaseExpiresAt: now.addingTimeInterval(60),
        idempotencyKey: "idem-1",
        payloadHash: "payload-hash"
    )

    #expect(item.status == .leased)
    #expect(item.attemptCount == 2)
    #expect(item.lockedBy == "worker-1")
    #expect(item.leaseExpiresAt != nil)
    #expect(item.idempotencyKey == "idem-1")
}

@Test func memoryOSEntitySupportsTemporalKernelFields() {
    let entity = MemoryOSEntity(
        stableKey: MemoryOSStableKeyBuilder.stableKey(type: "project", name: "Connor Memory OS"),
        entityType: "project",
        name: "Connor Memory OS",
        aliases: ["Memory OS"],
        summary: "Production memory system",
        confidence: 0.95,
        validFrom: Date(timeIntervalSince1970: 3_000)
    )

    #expect(entity.stableKey == "default:project:connor-memory-os")
    #expect(entity.aliases == ["Memory OS"])
    #expect(entity.validFrom != nil)
}
