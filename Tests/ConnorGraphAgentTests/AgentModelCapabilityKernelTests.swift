import Foundation
import Testing
import ConnorGraphAgent

@Test func imageDataURLParserParsesImageMimeTypeAndBase64Payload() throws {
    let parsed = try #require(AgentImageDataURLParser.parse("data:image/png;base64,iVBORw0KGgo="))

    #expect(parsed.mimeType == "image/png")
    #expect(parsed.base64 == "iVBORw0KGgo=")
    #expect(parsed.original == "data:image/png;base64,iVBORw0KGgo=")
}

@Test func imageDataURLParserRejectsNonImageDataURL() throws {
    #expect(AgentImageDataURLParser.parse("data:text/plain;base64,SGVsbG8=") == nil)
}

@Test func imageDataURLParserRejectsMalformedDataURL() throws {
    #expect(AgentImageDataURLParser.parse("not-a-data-url") == nil)
    #expect(AgentImageDataURLParser.parse("data:image/png,missing-base64-marker") == nil)
}

@Test func explicitVisionSupportOverridesHeuristics() throws {
    let profile = AgentModelCapabilityKernel.profile(
        providerKind: .openAICompatible,
        modelID: "text-only-test",
        explicitVisionSupport: true
    )

    #expect(profile.supportsVision)
    #expect(profile.confidence == .explicit)
    #expect(profile.signals.contains(.explicitConfig))
}

@Test func openAICompatibleTextOnlyModelDoesNotAdvertiseVisionByDefault() throws {
    let profile = AgentModelCapabilityKernel.profile(providerKind: .openAICompatible, modelID: "text-only-test")

    #expect(profile.supportsVision == false)
}

@Test func openAICompatibleVisionNamedModelAdvertisesVision() throws {
    let profile = AgentModelCapabilityKernel.profile(providerKind: .openAICompatible, modelID: "qwen3-vl-plus")

    #expect(profile.supportsVision)
    #expect(profile.signals.contains(.modelNameHeuristic))
}

@Test func anthropicClaudeModelAdvertisesVision() throws {
    let profile = AgentModelCapabilityKernel.profile(providerKind: .anthropicCompatible, modelID: "claude-3-5-sonnet-latest")

    #expect(profile.supportsVision)
}

@Test func visionSendDecisionAllowsTextOnlyRequestEvenWhenVisionUnsupported() throws {
    let profile = AgentModelCapabilityKernel.profile(providerKind: .openAICompatible, modelID: "text-only-test")
    let request = AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Hello")])

    #expect(AgentModelCapabilityKernel.visionSendDecision(profile: profile, request: request) == .allowed)
}

@Test func visionSendDecisionDeniesImageRequestWhenVisionUnsupported() throws {
    let profile = AgentModelCapabilityKernel.profile(providerKind: .openAICompatible, modelID: "text-only-test")
    let request = AgentModelRequest(messages: [
        AgentModelMessage(
            role: .user,
            content: "Describe this image",
            contentParts: [.text("Describe this image"), .imageDataURL("data:image/png;base64,iVBORw0KGgo=", mimeType: "image/png")]
        )
    ])

    if case .denied(let reason) = AgentModelCapabilityKernel.visionSendDecision(profile: profile, request: request) {
        #expect(reason.contains("does not support vision"))
    } else {
        Issue.record("Expected image request to be denied")
    }
}

@Test func mimoV25AdvertisesVision() throws {
    let profile = AgentModelCapabilityKernel.profile(providerKind: .openAICompatible, modelID: "mimo-v2.5")
    #expect(profile.supportsVision)
    #expect(profile.signals.contains(.modelNameHeuristic))
}

@Test func mimoV25ProDoesNotAdvertiseVision() throws {
    let profile = AgentModelCapabilityKernel.profile(providerKind: .openAICompatible, modelID: "mimo-v2.5-pro")
    #expect(profile.supportsVision == false)
}

@Test func mimoV25ProUltraSpeedDoesNotAdvertiseVision() throws {
    let profile = AgentModelCapabilityKernel.profile(providerKind: .openAICompatible, modelID: "mimo-v2.5-pro-ultraspeed")
    #expect(profile.supportsVision == false)
}

@Test func mimoV25TTSDoesNotAdvertiseVision() throws {
    let profile = AgentModelCapabilityKernel.profile(providerKind: .openAICompatible, modelID: "mimo-v2.5-tts")
    #expect(profile.supportsVision == false)
}

@Test func mimoV2OmniAdvertisesVision() throws {
    let profile = AgentModelCapabilityKernel.profile(providerKind: .openAICompatible, modelID: "mimo-v2-omni")
    #expect(profile.supportsVision)
}

@Test func visionSendDecisionAllowsImageRequestWhenVisionSupported() throws {
    let profile = AgentModelCapabilityKernel.profile(providerKind: .openAICompatible, modelID: "gpt-4o-mini")
    let request = AgentModelRequest(messages: [
        AgentModelMessage(
            role: .user,
            content: "Describe this image",
            contentParts: [.text("Describe this image"), .imageDataURL("data:image/png;base64,iVBORw0KGgo=", mimeType: "image/png")]
        )
    ])

    #expect(AgentModelCapabilityKernel.visionSendDecision(profile: profile, request: request) == .allowed)
    #expect(request.containsImageInput)
    #expect(request.imageInputCount == 1)
}

// MARK: - stripImageContent tests

@Test func stripImageContent_removesImagePartsPreservesText() throws {
    let request = AgentModelRequest(messages: [
        AgentModelMessage(role: .system, content: "You are helpful."),
        AgentModelMessage(
            role: .user,
            content: "Describe this image",
            contentParts: [.text("Describe this image"), .imageDataURL("data:image/png;base64,iVBORw0KGgo=", mimeType: "image/png")]
        )
    ])
    let stripped = request.stripImageContent()

    #expect(stripped.containsImageInput == false)
    #expect(stripped.messages.count == 2)
    #expect(stripped.messages[0].content == "You are helpful.")
    #expect(stripped.messages[0].contentParts == nil)
    #expect(stripped.messages[1].content == "Describe this image")
    #expect(stripped.messages[1].contentParts?.isEmpty == false)
    #expect(stripped.messages[1].contentParts?.allSatisfy { $0.kind == .text } == true)
}

@Test func stripImageContent_handlesImageOnlyMessage() throws {
    let request = AgentModelRequest(messages: [
        AgentModelMessage(
            role: .user,
            content: "",
            contentParts: [.imageDataURL("data:image/jpeg;base64,/9j/4AAQ=", mimeType: "image/jpeg")]
        )
    ])
    let stripped = request.stripImageContent()

    #expect(stripped.containsImageInput == false)
    #expect(stripped.messages[0].content == "[图片内容已忽略]")
    #expect(stripped.messages[0].contentParts == nil)
}

@Test func stripImageContent_noImagesReturnsSameRequest() throws {
    let request = AgentModelRequest(messages: [
        AgentModelMessage(role: .user, content: "Hello world")
    ])
    let stripped = request.stripImageContent()

    #expect(stripped.messages == request.messages)
}

@Test func stripImageContent_multipleImagePartsInMessage() throws {
    let request = AgentModelRequest(messages: [
        AgentModelMessage(
            role: .user,
            content: "Compare these",
            contentParts: [
                .text("Compare these"),
                .imageDataURL("data:image/png;base64,AAA=", mimeType: "image/png"),
                .imageDataURL("data:image/png;base64,BBB=", mimeType: "image/png"),
                .text("and describe differences")
            ]
        )
    ])
    let stripped = request.stripImageContent()

    #expect(stripped.containsImageInput == false)
    #expect(stripped.messages[0].content == "Compare these\nand describe differences")
    #expect(stripped.messages[0].contentParts?.count == 2)
    #expect(stripped.messages[0].contentParts?.allSatisfy { $0.kind == .text } == true)
}
