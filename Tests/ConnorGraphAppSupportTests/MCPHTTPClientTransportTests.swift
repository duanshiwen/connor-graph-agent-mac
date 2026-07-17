import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Test func mcpHTTPTransportDecodesSSEJSONRPCResponse() throws {
    let body = "event: message\r\ndata: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2025-06-18\"}}\r\n\r\n"

    let response = try MCPHTTPClientTransport.decodeEventStream(
        Data(body.utf8),
        expectedID: .number(1)
    )

    #expect(response.id == .number(1))
    #expect(response.result?.objectValue?["protocolVersion"] == .string("2025-06-18"))
}

@Test func mcpHTTPTransportIgnoresSSENotificationsAndMatchesResponseID() throws {
    let body = "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\"}\n\ndata: {\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{\"tools\":[]}}\n\n"

    let response = try MCPHTTPClientTransport.decodeEventStream(
        Data(body.utf8),
        expectedID: .number(7)
    )

    #expect(response.id == .number(7))
    #expect(response.result?.objectValue?["tools"] == .array([]))
}

@Test func mcpHTTPTransportRejectsSSEWithoutMatchingResponse() {
    let body = "data: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{}}\n\n"

    #expect(throws: MCPHTTPClientTransportError.self) {
        try MCPHTTPClientTransport.decodeEventStream(
            Data(body.utf8),
            expectedID: .number(1)
        )
    }
}
