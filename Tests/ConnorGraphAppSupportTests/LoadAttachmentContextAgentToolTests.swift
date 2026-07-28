import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport

@Test func loadAttachmentContextReturnsImageAsModelOnlyMultimodalContent() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()
    let source = root.appendingPathComponent("source.png")
    let bytes = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1])
    try bytes.write(to: source)
    let store = AppSessionAttachmentStore(paths: paths)
    let manifest = try store.importFile(at: source, sessionID: "session")
    let tool = LoadAttachmentContextAgentTool(store: store)
    let context = AgentToolExecutionContext(
        runID: "run",
        sessionID: "session",
        groupID: "default",
        userPrompt: "inspect",
        toolCallID: "call",
        policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
    )

    let result = try await tool.execute(
        arguments: AgentToolArguments(values: ["attachmentIDs": .array([.string(manifest.id)])]),
        context: context
    )

    let part = try #require(result.modelContentParts?.first)
    #expect(part.kind == .imageDataURL)
    #expect(part.dataURL?.contains(bytes.base64EncodedString()) == true)
    #expect(result.contentText.contains(manifest.id))
}

@Test func loadAttachmentContextReportsUnsupportedAudioRepresentationWithoutInliningBinary() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()
    let source = root.appendingPathComponent("source.mp3")
    try Data([0x49, 0x44, 0x33, 1]).write(to: source)
    let store = AppSessionAttachmentStore(paths: paths)
    let manifest = try store.importFile(at: source, sessionID: "session")
    let tool = LoadAttachmentContextAgentTool(store: store)
    let context = AgentToolExecutionContext(
        runID: "run",
        sessionID: "session",
        groupID: "default",
        userPrompt: "listen",
        toolCallID: "call",
        policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
    )

    let result = try await tool.execute(
        arguments: AgentToolArguments(values: ["attachmentIDs": .array([.string(manifest.id)])]),
        context: context
    )

    #expect(result.modelContentParts == nil)
    #expect(result.contentText.contains("No model-compatible"))
}
