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
