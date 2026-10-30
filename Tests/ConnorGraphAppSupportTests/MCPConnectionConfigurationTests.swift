import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Test func mcpInvocationRejectsConfigurationChangedWhileAwaitingApproval() throws {
    let source = MCPSourceRuntimeConfiguration(sourceID: "test-source", displayName: "Test", transport: .http(url: URL(string: "https://example.com/mcp")!), status: .enabled)
    try MCPClientPool.validateExecutionConfiguration(expected: source, current: source)
    var changed = source
    changed.transport = .http(url: URL(string: "https://other.example.com/mcp")!)
    #expect(throws: MCPClientPoolError.sourceConfigurationChanged(source.sourceID)) {
        try MCPClientPool.validateExecutionConfiguration(expected: source, current: changed)
    }
    changed = source
    changed.status = .disabled
    #expect(throws: MCPClientPoolError.sourceNotEnabled(source.sourceID)) {
        try MCPClientPool.validateExecutionConfiguration(expected: source, current: changed)
    }
    changed = source
    changed.allowedCapabilities = []
    #expect(throws: MCPClientPoolError.sourceConfigurationChanged(source.sourceID)) {
        try MCPClientPool.validateExecutionConfiguration(expected: source, current: changed)
    }
}
