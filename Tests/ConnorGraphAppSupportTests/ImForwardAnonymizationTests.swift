import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
import ConnorGraphStore

// MARK: - Fixtures

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("im-forward-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeImStore() throws -> SQLiteImStore {
    try SQLiteImStore(databaseURL: try temporaryDirectory().appendingPathComponent("im.sqlite"))
}

private func makeMemoryStore() throws -> SQLiteMemoryOSStore {
    let store = try SQLiteMemoryOSStore(path: try temporaryDirectory().appendingPathComponent("memory.sqlite").path)
    try store.migrate()
    return store
}

private func message(
    id: String,
    conversationId: String = "peer:9",
    senderId: Int64,
    senderName: String = "",
    content: String
) -> ImMessage {
    ImMessage(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        senderName: senderName,
        messageType: "text",
        content: content,
        status: .delivered,
        createdAt: 1_000,
        extraJson: "{}"
    )
}

private func conversation(id: String = "peer:9") -> ImConversation {
    ImConversation(id: id, kind: .peer, peerUserId: 9, title: "张三", lastMessageAt: 1_000, updatedAt: 1_000)
}

/// Deterministic token generator yielding a scripted sequence.
private final class ScriptedTokens: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String]

    init(_ tokens: [String]) { self.tokens = tokens }

    func next() -> String {
        lock.withLock { tokens.isEmpty ? "@CX000000" : tokens.removeFirst() }
    }
}

// MARK: - ImAliasTokens

@Test func imAliasTokensRecognizeAndScan() {
    #expect(ImAliasTokens.isToken("@CX1A2B3C"))
    #expect(ImAliasTokens.isToken("  @CXFFFFFF \n"))
    #expect(!ImAliasTokens.isToken("@CX1a2b3c"))
    #expect(!ImAliasTokens.isToken("@CX12345"))
    #expect(!ImAliasTokens.isToken("说 @CX1A2B3C 好"))
    #expect(ImAliasTokens.firstToken(in: "他是 @CXAB01EF，一个代号") == "@CXAB01EF")
    #expect(ImAliasTokens.firstToken(in: "没有代号") == nil)
    #expect(ImAliasTokens.tokens(in: "@CX000001 和 @CX000002 和 @CX000001") == ["@CX000001", "@CX000002"])
}

// MARK: - ImTranscriptAnonymizer

@Test func anonymizerAllocatesAndReusesPersistedToken() async throws {
    let store = try makeImStore()
    let anonymizer = ImTranscriptAnonymizer(store: store, now: { 42 })
    let first = try await anonymizer.allocateAlias(senderId: 9, conversationId: "peer:9", personProfileID: "contact-1", displayName: "张三")
    #expect(ImAliasTokens.isToken(first))
    let second = try await anonymizer.allocateAlias(senderId: 9, conversationId: "peer:9", personProfileID: "contact-1", displayName: "张三")
    #expect(second == first)
    let persisted = try await store.aliasBySender(senderId: 9)
    #expect(persisted?.aliasToken == first)
    #expect(persisted?.personProfileID == "contact-1")
    #expect(persisted?.createdAt == 42)
}

@Test func anonymizerRegeneratesOnStoreCollision() async throws {
    let store = try makeImStore()
    let script = ScriptedTokens(["@CXAAAAAA", "@CXAAAAAA", "@CXBBBBBB"])
    let anonymizer = ImTranscriptAnonymizer(store: store, now: { 1 }, generateToken: { script.next() })
    let first = try await anonymizer.allocateAlias(senderId: 1, conversationId: "peer:1", personProfileID: "c1", displayName: "甲")
    #expect(first == "@CXAAAAAA")
    // The scripted generator collides once with the persisted token, then recovers.
    let second = try await anonymizer.allocateAlias(senderId: 2, conversationId: "peer:2", personProfileID: "c2", displayName: "乙")
    #expect(second == "@CXBBBBBB")
}

@Test func anonymizerRefreshesPersonBindingWithoutChangingToken() async throws {
    let store = try makeImStore()
    let script = ScriptedTokens(["@CXAAAAAA"])
    let anonymizer = ImTranscriptAnonymizer(store: store, now: { 42 }, generateToken: { script.next() })
    let first = try await anonymizer.allocateAlias(
        senderId: 9,
        conversationId: "group:old",
        personProfileID: "contact-old",
        displayName: "旧名称"
    )
    let second = try await anonymizer.allocateAlias(
        senderId: 9,
        conversationId: "peer:9",
        personProfileID: "contact-new",
        displayName: "新名称"
    )

    #expect(second == first)
    let persisted = try await store.aliasBySender(senderId: 9)
    #expect(persisted?.aliasToken == "@CXAAAAAA")
    #expect(persisted?.imConversationId == "peer:9")
    #expect(persisted?.personProfileID == "contact-new")
    #expect(persisted?.displayName == "新名称")
    #expect(persisted?.createdAt == 42)
}

@Test func anonymizeMasksPiiAndReplacesNamesLongestFirst() async throws {
    let store = try makeImStore()
    let script = ScriptedTokens(["@CX111111"])
    let anonymizer = ImTranscriptAnonymizer(store: store, now: { 1 }, generateToken: { script.next() })
    let messages = [
        message(id: "m1", senderId: 9, senderName: "张三", content: "我是张三丰，张三是我小号，手机 13812345678"),
        message(id: "m2", senderId: 1, content: "收到，我的邮箱 self@example.com 不变"),
        message(id: "m3", senderId: 9, senderName: "张三", content: "身份证 11010119900307687X 银行卡 6222020200112233"),
    ]
    let result = try await anonymizer.anonymize(
        messages: messages,
        conversation: conversation(),
        selfUserId: 1,
        friendLookup: { senderId in
            senderId == 9 ? ImParticipantInfo(personProfileID: "contact-1", displayName: "张三丰") : nil
        }
    )
    let lines = result.transcriptText.components(separatedBy: "\n")
    #expect(lines.count == 3)
    // Longest-first replacement: 张三丰 must not decay into `@CX111111丰`.
    #expect(lines[0] == "@CX111111：我是@CX111111，@CX111111是我小号，手机 「[已隐藏]」")
    #expect(lines[1] == "我：收到，我的邮箱 「[已隐藏]」 不变")
    // 18-digit ID card masked before the 16-19 digit bank card pattern could eat it.
    #expect(lines[2] == "@CX111111：身份证 「[已隐藏]」 银行卡 「[已隐藏]」")
    #expect(result.tokensUsed == ["@CX111111"])
}

@Test func anonymizeUsesEphemeralTokenForUnboundSender() async throws {
    let store = try makeImStore()
    let script = ScriptedTokens(["@CX111111", "@CX222222"])
    let anonymizer = ImTranscriptAnonymizer(store: store, now: { 1 }, generateToken: { script.next() })
    let messages = [
        message(id: "m1", conversationId: "group:g1", senderId: 9, senderName: "张三", content: "早"),
        message(id: "m2", conversationId: "group:g1", senderId: 8, senderName: "路人", content: "早上好"),
        message(id: "m3", conversationId: "group:g1", senderId: 8, senderName: "路人", content: "开工"),
    ]
    let result = try await anonymizer.anonymize(
        messages: messages,
        conversation: ImConversation(id: "group:g1", kind: .group, groupId: "g1", title: "群", lastMessageAt: 1, updatedAt: 1),
        selfUserId: 1,
        friendLookup: { senderId in
            senderId == 9 ? ImParticipantInfo(personProfileID: "contact-1", displayName: "张三") : nil
        }
    )
    let lines = result.transcriptText.components(separatedBy: "\n")
    // The unbound sender reuses one ephemeral token across its messages, and the
    // sender name from the message is still replaced in bodies.
    #expect(lines[1] == "@CX222222：早上好")
    #expect(lines[2] == "@CX222222：开工")
    #expect(result.tokensUsed == ["@CX111111", "@CX222222"])
    // Ephemeral tokens are never persisted.
    #expect(try await store.aliasBySender(senderId: 8) == nil)
    #expect(try await store.aliasBySender(senderId: 9)?.aliasToken == "@CX111111")
}

// MARK: - ImForwardComposer

@Test func forwardComposerBuildsBatchIdAndMessage() {
    #expect(
        ImForwardComposer.batchID(conversationId: "peer:9", messageIds: ["m3", "m1", "m2"])
            == "im-forward:peer:9:m1,m2,m3"
    )
    let plain = ImForwardComposer.composeMessage(caption: "  ", transcriptText: "我：早")
    #expect(plain == ImForwardComposer.disclaimer + "我：早")
    let captioned = ImForwardComposer.composeMessage(caption: " 帮我总结 ", transcriptText: "我：早")
    #expect(captioned == "帮我总结\n\n" + ImForwardComposer.disclaimer + "我：早")
    #expect(ImForwardComposer.disclaimer.contains("@CXxxxxxx"))
}

// MARK: - ImForwardTranscriptIngestor

@Test func forwardIngestorIsIdempotentPerBatch() throws {
    let store = try makeMemoryStore()
    let facade = AppMemoryOSFacade(store: store)
    let ingestor = ImForwardTranscriptIngestor(facade: facade)
    let batchID = ImForwardComposer.batchID(conversationId: "peer:9", messageIds: ["m1", "m2"])

    #expect(try ingestor.ingest(batchID: batchID, transcriptText: "我：早\n@CX111111：早上好"))
    #expect(try !ingestor.ingest(batchID: batchID, transcriptText: "我：早\n@CX111111：早上好"))
    let escaped = batchID.replacingOccurrences(of: "'", with: "''")
    let count = try store.query(sql: "SELECT COUNT(*) FROM memory_l0_provenance_objects WHERE source_id = '\(escaped)';")
    #expect(count.first?.first == "1")
    #expect(try !ingestor.ingest(batchID: "im-forward:peer:9:m9", transcriptText: "   "))
}

// MARK: - Projection alias resolution

private func forwardedExtractionJSON(tokenName: String) throws -> String {
    let output = GraphStructuredExtractionOutput(
        entities: [
            GraphStructuredExtractedEntity(localID: "person-1", name: tokenName, entityKind: .personObject, scope: .personal, confidence: 0.9, evidenceSpanIDs: ["span-1"]),
            GraphStructuredExtractedEntity(localID: "project-1", name: "Connor Memory OS", entityKind: .workObject, scope: .project, confidence: 0.9, evidenceSpanIDs: ["span-1"])
        ],
        statements: [
            GraphStructuredExtractedStatement(explicitID: "stmt-1", subjectLocalID: "person-1", predicate: .relatedTo, objectLocalID: "project-1", statementText: "\(tokenName) 正在推进 Connor Memory OS。", confidence: 0.9, evidenceSpanIDs: ["span-1"])
        ],
        evidenceSpans: [GraphStructuredEvidenceSpan(id: "span-1", text: "\(tokenName) 正在推进 Connor Memory OS。")]
    )
    return String(data: try JSONEncoder().encode(output), encoding: .utf8)!
}

@Test func projectionRedirectsTokenEntityToBoundPerson() async throws {
    let imStore = try makeImStore()
    let memoryStore = try makeMemoryStore()
    // Bound alias: token → person profile contact-1 → existing person memory entity.
    try await imStore.insertAlias(ImForwardAlias(
        aliasToken: "@CXABCDEF", senderId: 9, imConversationId: "peer:9",
        personProfileID: "contact-1", displayName: "张三", createdAt: 1
    ))
    let personEntityID = AppPersonMemoryBindingService.entityID(forStableKey: AppPersonMemoryBindingService.stableKey(for: ContactID(rawValue: "contact-1")))
    try memoryStore.upsert(entity: MemoryOSEntity(id: personEntityID, stableKey: "person-profile:contact-1", entityType: "person", name: "张三", confidence: 1.0))

    var facade = AppMemoryOSFacade(store: memoryStore)
    let rewriter = ImForwardAliasProjectionRewriter(imStore: imStore, memoryStore: memoryStore)
    facade.projectionBatchRewriter = { rewriter.rewrite($0) }

    let summary = try facade.projectAndRecordLLMArtifact(
        rawContent: try forwardedExtractionJSON(tokenName: "@CXABCDEF"),
        modelID: "test-model",
        schemaName: "GraphStructuredExtractionOutput"
    )
    #expect(summary.accepted)
    // No @CX garbage entity lands in L4; the fact hangs off the real person.
    let names = try memoryStore.query(sql: "SELECT name FROM memory_l4_entities;").compactMap(\.first)
    #expect(!names.contains("@CXABCDEF"))
    #expect(names.contains("张三"))
    #expect(names.contains("Connor Memory OS"))
    let subjects = try memoryStore.query(sql: "SELECT entity_id FROM memory_l4_entity_statements;").compactMap(\.first)
    #expect(subjects == [personEntityID])
    // L2 keeps the token verbatim: only the L4 identity layer resolves it.
    let nodeNames = try memoryStore.query(sql: "SELECT name FROM memory_l2_nodes;").compactMap(\.first)
    #expect(nodeNames.contains("@CXABCDEF"))
}

@Test func projectionKeepsUnresolvableTokenEntity() async throws {
    let imStore = try makeImStore()
    let memoryStore = try makeMemoryStore()
    var facade = AppMemoryOSFacade(store: memoryStore)
    let rewriter = ImForwardAliasProjectionRewriter(imStore: imStore, memoryStore: memoryStore)
    facade.projectionBatchRewriter = { rewriter.rewrite($0) }

    // No alias row: the token degrades to a plain named entity without blocking the batch.
    let summary = try facade.projectAndRecordLLMArtifact(
        rawContent: try forwardedExtractionJSON(tokenName: "@CXFFFFFF"),
        modelID: "test-model",
        schemaName: "GraphStructuredExtractionOutput"
    )
    #expect(summary.accepted)
    let names = try memoryStore.query(sql: "SELECT name FROM memory_l4_entities;").compactMap(\.first)
    #expect(names.contains("@CXFFFFFF"))
    #expect(names.contains("Connor Memory OS"))
}

@Test func projectionCreatesMissingBoundPersonBeforeRedirectingToken() async throws {
    let imStore = try makeImStore()
    let memoryStore = try makeMemoryStore()
    try await imStore.insertAlias(ImForwardAlias(
        aliasToken: "@CXABCDEF", senderId: 9, imConversationId: "peer:9",
        personProfileID: "contact-1", displayName: "张三", createdAt: 1
    ))
    let stableKey = AppPersonMemoryBindingService.stableKey(for: ContactID(rawValue: "contact-1"))
    let personEntityID = AppPersonMemoryBindingService.entityID(forStableKey: stableKey)
    #expect(try memoryStore.entity(id: personEntityID) == nil)

    var facade = AppMemoryOSFacade(store: memoryStore)
    let rewriter = ImForwardAliasProjectionRewriter(imStore: imStore, memoryStore: memoryStore)
    facade.projectionBatchRewriter = { rewriter.rewrite($0) }
    let summary = try facade.projectAndRecordLLMArtifact(
        rawContent: try forwardedExtractionJSON(tokenName: "@CXABCDEF"),
        modelID: "test-model",
        schemaName: "GraphStructuredExtractionOutput"
    )

    #expect(summary.accepted)
    let person = try memoryStore.entity(id: personEntityID)
    #expect(person?.stableKey == stableKey)
    #expect(person?.name == "张三")
    #expect(person?.metadata["person_profile_id"] == "contact-1")
    #expect(person?.metadata["source"] == "im_forward_alias")
    let names = try memoryStore.query(sql: "SELECT name FROM memory_l4_entities;").compactMap(\.first)
    #expect(!names.contains("@CXABCDEF"))
    let subjects = try memoryStore.query(sql: "SELECT entity_id FROM memory_l4_entity_statements;").compactMap(\.first)
    #expect(subjects == [personEntityID])
}

@Test func projectionRewriterResolvesLowercasedTokenName() throws {
    let rewriter = ImForwardAliasProjectionRewriter(resolvePersonEntityID: { token in
        token == "@CXABCDEF" ? "person:person-profile:contact-1" : nil
    })
    let batch = MemoryOSProjectionBatch(
        artifactID: "artifact-1",
        entities: [
            MemoryOSEntity(id: "l4-entity:x", stableKey: "x", entityType: "person", name: " @cxabcdef "),
            MemoryOSEntity(id: "l4-entity:y", stableKey: "y", entityType: "person", name: "李四")
        ],
        entityStatements: [
            MemoryOSEntityStatement(id: "s1", entityID: "l4-entity:y", predicate: .relatedTo, objectEntityID: "l4-entity:x", text: "李四认识 @cxabcdef", assertionKind: .observed, confidence: 1, validAt: Date(), committedAt: Date(), evidenceSpanIDs: [], sourceArtifactID: "artifact-1")
        ]
    )
    let rewritten = rewriter.rewrite(batch)
    #expect(rewritten.entities.map(\.id) == ["l4-entity:y"])
    #expect(rewritten.entityStatements.first?.objectEntityID == "person:person-profile:contact-1")
    #expect(rewritten.entityStatements.first?.entityID == "l4-entity:y")
}
