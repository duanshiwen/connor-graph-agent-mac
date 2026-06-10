import Foundation
import Testing
import ConnorGraphMemory

@Test func memoryDistillationResultAggregatesCandidatesByKind() throws {
    let profile = MemoryDistillationCandidate(
        id: "profile-1",
        kind: .profileFact,
        content: "用户偏好结构化回答。"
    )
    let decision = MemoryDistillationCandidate(
        id: "decision-1",
        kind: .decision,
        content: "Connor 图谱定位为后台记忆基础设施。"
    )
    let preference = MemoryDistillationCandidate(
        id: "preference-1",
        kind: .preference,
        content: "数学公式不使用行内 LaTeX。"
    )
    let result = MemoryDistillationResult(
        sessionID: "session-1",
        sourceBufferID: "buffer-1",
        profileFactCandidates: [profile],
        decisionCandidates: [decision],
        preferenceCandidates: [preference]
    )

    #expect(result.proposedCandidates.map(\.id) == ["profile-1", "decision-1", "preference-1"])
    #expect(result.candidates(kind: .profileFact) == [profile])
    #expect(result.candidates(kind: .decision) == [decision])
}

@Test func memoryDistillationTraceCarriesTriggerReasonsAndInputShape() throws {
    let createdAt = Date(timeIntervalSince1970: 5_000)
    let trace = MemoryDistillationTrace(
        model: "distiller-model",
        promptVersion: "memory-distill-v1",
        inputBundleCount: 20,
        inputTokenEstimate: 8_000,
        outputTokenEstimate: 900,
        triggerReasons: [.bundleCountReached, .highValueSignal],
        createdAt: createdAt
    )

    #expect(trace.model == "distiller-model")
    #expect(trace.promptVersion == "memory-distill-v1")
    #expect(trace.inputBundleCount == 20)
    #expect(trace.triggerReasons == [.bundleCountReached, .highValueSignal])
    #expect(trace.createdAt == createdAt)
}

@Test func memoryDistillationSourceRefPreservesBundleMessagesArtifactsAndQuote() throws {
    let ref = MemoryDistillationSourceRef(
        id: "ref-1",
        bundleID: "bundle-1",
        messageIDs: ["u1", "a1"],
        artifactIDs: ["browser-1"],
        quote: "不要每条 message 直接进入 episode。"
    )

    #expect(ref.bundleID == "bundle-1")
    #expect(ref.messageIDs == ["u1", "a1"])
    #expect(ref.artifactIDs == ["browser-1"])
    #expect(ref.quote.contains("episode"))
}
