import Foundation
import Testing
import ConnorGraphCore

@Test func agentMessageDecodesLegacyJSONWithEmptyAttachments() throws {
    let json = """
    {
      "id": "message-1",
      "role": "user",
      "content": "Hello",
      "createdAt": 1000,
      "citations": []
    }
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970

    let message = try decoder.decode(AgentMessage.self, from: json)

    #expect(message.id == "message-1")
    #expect(message.role == .user)
    #expect(message.attachments.isEmpty)
}

@Test func agentMessageAttachmentRefRoundTripsThroughCodable() throws {
    let ref = AgentMessageAttachmentRef(
        id: "attachment-1",
        displayName: "notes.md",
        kind: .markdown,
        byteCount: 42,
        lifecycleStatus: .ready,
        extractionStatus: .extracted,
        manifestRelativePath: "attachments/attachment-1/manifest.json",
        previewText: "Meeting notes"
    )

    let data = try JSONEncoder().encode(ref)
    let decoded = try JSONDecoder().decode(AgentMessageAttachmentRef.self, from: data)

    #expect(decoded == ref)
}

@Test func appendUserMessageStoresAttachmentRefs() {
    let ref = AgentMessageAttachmentRef(
        id: "attachment-1",
        displayName: "notes.md",
        kind: .markdown,
        byteCount: 42,
        lifecycleStatus: .ready,
        extractionStatus: .extracted,
        manifestRelativePath: "attachments/attachment-1/manifest.json",
        previewText: "Meeting notes"
    )
    var session = AgentSession(id: "session-1")

    let message = session.appendUserMessage("Please summarize this.", attachments: [ref])

    #expect(message.attachments == [ref])
    #expect(session.messages.first?.attachments == [ref])
}

@Test func assistantMessagesDefaultToNoAttachments() {
    var session = AgentSession(id: "session-1")

    let message = session.appendAssistantMessage("Done")

    #expect(message.attachments.isEmpty)
}
