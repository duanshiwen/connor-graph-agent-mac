import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

private actor EditImageRequestRecorder { var request: AgentGeneratedMediaRequest?; func record(_ value: AgentGeneratedMediaRequest) { request = value } }
private func editImageContext(sessionID: String = "session-edit") -> AgentToolExecutionContext { AgentToolExecutionContext(runID: "run", sessionID: sessionID, groupID: "default", userPrompt: "Edit image", toolCallID: "call", policyEngine: AgentPolicyEngine(permissionMode: .allowAll)) }

@Test func editImageToolResolvesSessionAttachmentAndCreatesNewAttachment() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true); defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths(applicationSupportDirectory: root); try paths.ensureDirectoryHierarchy(); let store = AppSessionAttachmentStore(paths: paths)
    let sourceURL = root.appendingPathComponent("source.png"); try Data([1, 2, 3]).write(to: sourceURL)
    let source = try store.importFile(at: sourceURL, sessionID: "session-edit", origin: .userImported)
    let outputData = Data([4, 5, 6]); let recorder = EditImageRequestRecorder()
    let provider = AnyAgentModelProvider(modelID: "editable-image", capabilities: AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: false, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: true, generatedMediaCapabilities: [.imageInput, .imageGeneration, .imageEditing]), complete: { _ in AgentModelResponse(text: "unused") }, generateMedia: { request in AsyncThrowingStream { continuation in Task { await recorder.record(request); let url = root.appendingPathComponent("edited.png"); do { try outputData.write(to: url); continuation.yield(.completed(AgentGeneratedMediaArtifact(temporaryFileURL: url, mimeType: "image/png", byteCount: Int64(outputData.count), generationMetadata: AgentAttachmentGenerationMetadata(providerID: "test-editor", modelID: "editable-image")))); continuation.finish() } catch { continuation.finish(throwing: error) } } } })
    let tool = EditImageAgentTool(provider: provider, ingestionService: GeneratedMediaIngestionService(store: store), attachmentStore: store)
    let result = try await tool.execute(arguments: AgentToolArguments(values: ["prompt": .string("Make it warmer"), "attachment_id": .string(source.id)]), context: editImageContext())

    let request = await recorder.request; #expect(request?.imageAction == .edit); #expect(request?.inputAttachments == [source.messageRef]); #expect(request?.prompt == "Make it warmer")
    let payload = try JSONDecoder().decode(GeneratedImageToolResultPayload.self, from: Data(try #require(result.contentJSON).utf8)); #expect(payload.attachment.id != source.id); #expect(payload.attachment.kind == AgentAttachmentKind.image)
}

@Test func editImageToolRejectsProviderWithoutEditingCapabilityBeforeLoadingPath() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true); defer { try? FileManager.default.removeItem(at: root) }; let paths = AppStoragePaths(applicationSupportDirectory: root); try paths.ensureDirectoryHierarchy(); let store = AppSessionAttachmentStore(paths: paths)
    let provider = AnyAgentModelProvider(modelID: "generate-only", capabilities: AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: false, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false, generatedMediaCapabilities: [.imageGeneration]), complete: { _ in AgentModelResponse(text: "unused") }, generateMedia: { _ in AsyncThrowingStream { $0.finish() } })
    let tool = EditImageAgentTool(provider: provider, ingestionService: GeneratedMediaIngestionService(store: store), attachmentStore: store)
    do {
        _ = try await tool.execute(
            arguments: AgentToolArguments(values: ["prompt": .string("edit"), "attachment_id": .string("/tmp/forbidden.png")]),
            context: editImageContext(sessionID: "session")
        )
        Issue.record("Expected capability rejection")
    } catch {
        #expect(error as? EditImageAgentToolError == .providerDoesNotSupportEditing)
    }
}
