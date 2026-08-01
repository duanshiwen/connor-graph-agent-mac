import Foundation
import Testing
@testable import ConnorGraphAgent

@Test func fileCheckpointStoreSurvivesReconstruction() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("assistant-checkpoint-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("pending.json")
    let request = AgentChatRequest(runID: "run", sessionID: "session", userMessage: "send")
    let permission = AgentPermissionRequest(
        id: "approval",
        runID: "run",
        sessionID: "session",
        capability: .sendMail,
        toolName: "mail_send"
    )
    let checkpoint = AssistantApprovalCheckpoint(
        envelope: AssistantRunEnvelope(request: request),
        call: AgentToolCall(id: "call", name: "mail_send", argumentsJSON: "{}"),
        request: permission,
        effectKey: "effect"
    )

    try await FileAssistantRunCheckpointStore(fileURL: fileURL).save(checkpoint)
    let recovered = try await FileAssistantRunCheckpointStore(fileURL: fileURL).pending()

    #expect(recovered == [checkpoint])
}

@Test func effectIdentityIsStableAcrossJSONKeyOrder() {
    let first = AgentToolCall(name: "mail_send", argumentsJSON: #"{"to":"a","body":"b"}"#)
    let second = AgentToolCall(name: "mail_send", argumentsJSON: #"{"body":"b","to":"a"}"#)

    #expect(AssistantEffectIdentity.key(runID: "run", call: first) == AssistantEffectIdentity.key(runID: "run", call: second))
}
