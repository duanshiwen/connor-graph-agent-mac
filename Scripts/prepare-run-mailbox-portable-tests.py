"""Prepare isolated Swift tests of the production mailbox and model envelopes.

Xcode UI/integration builds still require Apple SDKs. Only ambient Core domain and
tool ports are stubbed here; mailbox implementation, model envelopes and XCTest
cases are copied verbatim from this checkout.
"""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parent.parent
output = root / '.build' / 'run-mailbox-portable'
for directory in ['Sources/ConnorGraphCore', 'Sources/ConnorGraphAgent', 'Tests/ConnorGraphAgentTests']:
    (output / directory).mkdir(parents=True, exist_ok=True)
(output / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "RunMailboxPortable", targets: [
 .target(name: "ConnorGraphCore"),
 .target(name: "ConnorGraphAgent", dependencies: ["ConnorGraphCore"]),
 .testTarget(name: "ConnorGraphAgentTests", dependencies: ["ConnorGraphAgent"])
])
''', encoding='utf-8')
(output / 'Sources/ConnorGraphCore/Ports.swift').write_text('''
public struct AgentMessageAttachmentRef: Codable, Sendable, Equatable { public var id: String = "" }
public struct PersonReference: Codable, Sendable, Equatable { public var id: String = "" }
''', encoding='utf-8')
(output / 'Sources/ConnorGraphAgent/ToolPorts.swift').write_text('''
import Foundation
public struct AgentToolCall: Codable, Sendable, Equatable {
 public var id: String; public var name: String; public var argumentsJSON: String
 public init(id: String, name: String, argumentsJSON: String) { self.id=id; self.name=name; self.argumentsJSON=argumentsJSON }
}
public struct AgentToolResult: Codable, Sendable, Equatable {
 public var toolCallID: String; public var toolName: String; public var contentText: String; public var contentJSON: String? = nil; public var modelContentParts: [AgentModelMessageContentPart]? = nil
 public init(toolCallID: String, toolName: String, contentText: String) { self.toolCallID=toolCallID; self.toolName=toolName; self.contentText=contentText }
}
public enum AgentToolInputSchema: Sendable { case string(description: String); case closedObject(properties: [String: Self], required: [String]) }
public enum AgentPermissionCapability: Sendable { case readSession }
public enum AgentToolError: Error { case invalidArguments(String) }
public struct AgentToolArguments { public func string(_ key: String) -> String? { nil } }
public struct AgentToolExecutionContext { public var sessionID: String; public var toolCallID: String }
public protocol AgentTool: Sendable {
 var name: String { get }; var description: String { get }; var permission: AgentPermissionCapability { get }; var inputSchema: AgentToolInputSchema { get }
 func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult
}
''', encoding='utf-8')
models = (root / 'Sources/ConnorGraphAgent/AgentModelProvider.swift').read_text(encoding='utf-8-sig')
models = models[:models.index('public enum AgentGeneratedMediaKind')]
(output / 'Sources/ConnorGraphAgent/ModelEnvelopes.swift').write_text(models, encoding='utf-8')
shutil.copyfile(root / 'Sources/ConnorGraphAgent/AgentRunMailbox.swift', output / 'Sources/ConnorGraphAgent/AgentRunMailbox.swift')
shutil.copyfile(root / 'Tests/ConnorGraphAgentTests/AgentRunMailboxTests.swift', output / 'Tests/ConnorGraphAgentTests/AgentRunMailboxTests.swift')
print(output)
