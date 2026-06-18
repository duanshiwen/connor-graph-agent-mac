import Foundation
import ConnorGraphCore

public protocol AgentContactRuntime: Sendable {
    func search(query: String) async throws -> [ContactRecord]
    func createDraft(record: ContactRecord) async throws -> ContactMutationDraft
    func commitDraft(id: String, approved: Bool) async throws -> ContactMutationDraft
}

public actor InMemoryAgentContactRuntime: AgentContactRuntime {
    private var contacts: [ContactRecord]
    private var drafts: [String: ContactMutationDraft] = [:]

    public init(contacts: [ContactRecord] = []) { self.contacts = contacts }

    public func search(query: String) async throws -> [ContactRecord] {
        let normalized = query.lowercased()
        return contacts.filter { $0.givenName.lowercased().contains(normalized) || $0.emails.contains { $0.email.lowercased().contains(normalized) } }
    }

    public func createDraft(record: ContactRecord) async throws -> ContactMutationDraft {
        let draft = ContactMutationDraft(record: record)
        drafts[draft.id] = draft
        return draft
    }

    public func commitDraft(id: String, approved: Bool) async throws -> ContactMutationDraft {
        guard var draft = drafts[id] else { throw AgentToolError.invalidArguments("Unknown contact draft") }
        guard approved else { throw AgentToolError.permissionDenied("Contact write approval required") }
        draft.status = .committed
        contacts.append(draft.record)
        drafts[id] = draft
        return draft
    }
}

public struct ContactSearchTool: AgentTool {
    public let runtime: any AgentContactRuntime
    public var name: String { "contact_search" }
    public var description: String { "Search governed contact records." }
    public var permission: AgentPermissionCapability { .readContacts }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["query": .string(description: "Contact query")], required: ["query"]) }
    public init(runtime: any AgentContactRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let records = try await runtime.search(query: arguments.string("query") ?? "")
        let json = try MailJSON.encode(records)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Found \(records.count) contacts", contentJSON: json)
    }
}

public struct ContactCreateDraftTool: AgentTool {
    public let runtime: any AgentContactRuntime
    public var name: String { "contact_create_draft" }
    public var description: String { "Create a contact mutation draft; does not write system Contacts." }
    public var permission: AgentPermissionCapability { .readContacts }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["email": .string(description: "Email"), "name": .string(description: "Display name")], required: ["email"] ) }
    public init(runtime: any AgentContactRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let email = arguments.string("email") else { throw AgentToolError.invalidArguments("email is required") }
        let record = ContactRecord(id: MailContactID(rawValue: email.lowercased()), givenName: arguments.string("name") ?? email, emails: [ContactEmailAddress(email: email)])
        let draft = try await runtime.createDraft(record: record)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Created contact draft \(draft.id); not committed", contentJSON: try MailJSON.encode(draft))
    }
}

public struct ContactCommitDraftTool: AgentTool {
    public let runtime: any AgentContactRuntime
    public var name: String { "contact_commit_draft" }
    public var description: String { "Commit a contact mutation draft after approval." }
    public var permission: AgentPermissionCapability { .mutateContacts }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["draftID": .string(description: "Draft ID"), "approved": .boolean(description: "Explicit approval")], required: ["draftID", "approved"]) }
    public init(runtime: any AgentContactRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let draftID = arguments.string("draftID") else { throw AgentToolError.invalidArguments("draftID is required") }
        let draft = try await runtime.commitDraft(id: draftID, approved: arguments.bool("approved") ?? false)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Committed approved contact draft \(draftID)", contentJSON: try MailJSON.encode(draft))
    }
}

public extension AgentToolRegistry {
    mutating func registerNativeContactTools(runtime: any AgentContactRuntime) {
        register(ContactSearchTool(runtime: runtime))
        register(ContactCreateDraftTool(runtime: runtime))
        register(ContactCommitDraftTool(runtime: runtime))
    }
}
