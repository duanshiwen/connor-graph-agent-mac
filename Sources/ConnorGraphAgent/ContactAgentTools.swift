import Foundation
import ConnorGraphCore

enum ContactJSON {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public protocol AgentContactRuntime: Sendable {
    func search(query: String) async throws -> [ContactRecord]
    func createDraft(record: ContactRecord) async throws -> ContactMutationDraft
    func commitDraft(id: String, approved: Bool) async throws -> ContactMutationDraft
    func listPeople() async throws -> [PersonProfile]
    func searchPeople(query: String) async throws -> [PersonProfile]
    func getPerson(id: ContactID) async throws -> PersonProfile?
    func createPerson(_ profile: PersonProfile, approved: Bool) async throws -> PersonProfile
    func updatePerson(id: ContactID, update: PersonProfileDraft, approved: Bool) async throws -> PersonProfile
    func deletePerson(id: ContactID, approved: Bool) async throws -> PersonProfile
    func mergePeople(sourceID: ContactID, targetID: ContactID, approved: Bool) async throws -> PersonProfile
}

public actor InMemoryAgentContactRuntime: AgentContactRuntime {
    private var contacts: [ContactRecord]
    private var people: [PersonProfile]
    private var drafts: [String: ContactMutationDraft] = [:]

    public init(contacts: [ContactRecord] = [], people: [PersonProfile]? = nil) {
        self.contacts = contacts
        self.people = people ?? contacts.map { PersonProfile(contactRecord: $0) }
    }

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
        people.append(PersonProfile(contactRecord: draft.record))
        drafts[id] = draft
        return draft
    }

    public func listPeople() async throws -> [PersonProfile] {
        people.filter(\.isActiveForDefaultContext).sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public func searchPeople(query: String) async throws -> [PersonProfile] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let active = try await listPeople()
        guard !normalized.isEmpty else { return active }
        return active.filter { profile in
            [
                profile.displayName,
                profile.givenName,
                profile.familyName,
                profile.organizationName ?? "",
                profile.jobTitle ?? "",
                profile.notes ?? "",
                profile.aliases.joined(separator: " "),
                profile.emails.map(\.email).joined(separator: " "),
                profile.phones.map(\.number).joined(separator: " "),
                profile.addresses.map(\.value).joined(separator: " ")
            ].contains { $0.lowercased().contains(normalized) }
        }
    }

    public func getPerson(id: ContactID) async throws -> PersonProfile? {
        people.first { $0.id == id }
    }

    public func createPerson(_ profile: PersonProfile, approved: Bool) async throws -> PersonProfile {
        guard approved else { throw AgentToolError.permissionDenied("Person profile write approval required") }
        people.removeAll { $0.id == profile.id }
        people.append(profile)
        contacts.removeAll { $0.id == profile.id }
        contacts.append(profile.contactRecord)
        return profile
    }

    public func updatePerson(id: ContactID, update: PersonProfileDraft, approved: Bool) async throws -> PersonProfile {
        guard approved else { throw AgentToolError.permissionDenied("Person profile write approval required") }
        guard let index = people.firstIndex(where: { $0.id == id }) else { throw AgentToolError.invalidArguments("Unknown person") }
        let updated = update.makeProfile(existing: people[index])
        people[index] = updated
        contacts.removeAll { $0.id == id }
        contacts.append(updated.contactRecord)
        return updated
    }

    public func deletePerson(id: ContactID, approved: Bool) async throws -> PersonProfile {
        guard approved else { throw AgentToolError.permissionDenied("Person profile delete approval required") }
        guard let index = people.firstIndex(where: { $0.id == id }) else { throw AgentToolError.invalidArguments("Unknown person") }
        people[index].status = .deleted
        people[index].updatedAt = Date()
        contacts.removeAll { $0.id == id }
        return people[index]
    }

    public func mergePeople(sourceID: ContactID, targetID: ContactID, approved: Bool) async throws -> PersonProfile {
        guard approved else { throw AgentToolError.permissionDenied("Person profile merge approval required") }
        guard sourceID != targetID else { throw AgentToolError.invalidArguments("Cannot merge a person into itself") }
        guard let sourceIndex = people.firstIndex(where: { $0.id == sourceID }) else { throw AgentToolError.invalidArguments("Unknown source person") }
        guard let targetIndex = people.firstIndex(where: { $0.id == targetID }) else { throw AgentToolError.invalidArguments("Unknown target person") }
        let source = people[sourceIndex]
        var target = people[targetIndex]
        target.aliases = Array(Set(target.aliases + [source.displayName] + source.aliases)).sorted()
        target.emails = mergeEmails(target.emails + source.emails)
        target.phones = mergePhones(target.phones + source.phones)
        target.addresses = mergeAddresses(target.addresses + source.addresses)
        target.updatedAt = Date()
        people[targetIndex] = target
        people[sourceIndex].status = .merged
        people[sourceIndex].mergedIntoID = targetID
        people[sourceIndex].updatedAt = Date()
        contacts.removeAll { $0.id == sourceID || $0.id == targetID }
        contacts.append(target.contactRecord)
        return target
    }

    private func mergeEmails(_ emails: [ContactEmailAddress]) -> [ContactEmailAddress] {
        var seen: Set<String> = []
        return emails.filter { seen.insert($0.email.lowercased()).inserted }
    }

    private func mergePhones(_ phones: [PersonPhoneNumber]) -> [PersonPhoneNumber] {
        var seen: Set<String> = []
        return phones.filter { seen.insert($0.number).inserted }
    }

    private func mergeAddresses(_ addresses: [PersonPostalAddress]) -> [PersonPostalAddress] {
        var seen: Set<String> = []
        return addresses.filter { seen.insert($0.value).inserted }
    }
}

public struct ContactSearchTool: AgentTool {
    public let runtime: any AgentContactRuntime
    public var name: String { "contact_search" }
    public var description: String { "Search governed contact records." }
    public var permission: AgentPermissionCapability { .readContacts }
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: ["query": .string(description: "Contact query")], required: ["query"]) }
    public init(runtime: any AgentContactRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let records = try await runtime.search(query: arguments.string("query") ?? "")
        let json = try ContactJSON.encode(records)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Found \(records.count) contacts", contentJSON: json)
    }
}

public struct ContactCreateDraftTool: AgentTool {
    public let runtime: any AgentContactRuntime
    public var name: String { "contact_create_draft" }
    public var description: String { "Create a contact mutation draft; does not write system Contacts." }
    public var permission: AgentPermissionCapability { .readContacts }
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: ["email": .string(description: "Email"), "name": .string(description: "Display name")], required: ["email"] ) }
    public init(runtime: any AgentContactRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let email = arguments.string("email") else { throw AgentToolError.invalidArguments("email is required") }
        let record = ContactRecord(id: ContactID(rawValue: email.lowercased()), givenName: arguments.string("name") ?? email, emails: [ContactEmailAddress(email: email)])
        let draft = try await runtime.createDraft(record: record)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Created contact draft \(draft.id); not committed", contentJSON: try ContactJSON.encode(draft))
    }
}

public struct ContactCommitDraftTool: AgentTool {
    public let runtime: any AgentContactRuntime
    public var name: String { "contact_commit_draft" }
    public var description: String { "Commit a contact mutation draft after approval." }
    public var permission: AgentPermissionCapability { .mutateContacts }
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: ["draftID": .string(description: "Draft ID"), "approved": .boolean(description: "Explicit approval")], required: ["draftID", "approved"]) }
    public init(runtime: any AgentContactRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let draftID = arguments.string("draftID") else { throw AgentToolError.invalidArguments("draftID is required") }
        let draft = try await runtime.commitDraft(id: draftID, approved: arguments.bool("approved") ?? false)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Committed approved contact draft \(draftID)", contentJSON: try ContactJSON.encode(draft))
    }
}

private func summarizePeople(_ people: [PersonProfile], prefix: String) -> String {
    let lines = people.prefix(20).map { person in
        var parts = [
            "person_id: \(person.id.rawValue)",
            "display_name: \(person.displayName)",
            "status: \(person.status.rawValue)"
        ]
        if let mergedIntoID = person.mergedIntoID {
            parts.append("merged_into_person_id: \(mergedIntoID.rawValue)")
        }
        if let notes = person.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append("notes: \(String(notes.prefix(160)))")
        }
        if !person.aliases.isEmpty {
            parts.append("aliases: \(person.aliases.prefix(5).joined(separator: ", "))")
        }
        return "- " + parts.joined(separator: " | ")
    }
    guard !lines.isEmpty else { return prefix }
    let suffix = people.count > lines.count ? ["... and \(people.count - lines.count) more people"] : []
    return ([prefix] + lines + suffix).joined(separator: "\n")
}

private func summarizePerson(_ person: PersonProfile?) -> String {
    guard let person else { return "Person not found" }
    var lines = [
        "Loaded person",
        "person_id: \(person.id.rawValue)",
        "display_name: \(person.displayName)",
        "status: \(person.status.rawValue)"
    ]
    if let mergedIntoID = person.mergedIntoID {
        lines.append("merged_into_person_id: \(mergedIntoID.rawValue)")
    }
    if !person.aliases.isEmpty {
        lines.append("aliases: \(person.aliases.joined(separator: ", "))")
    }
    if let organizationName = person.organizationName?.trimmingCharacters(in: .whitespacesAndNewlines), !organizationName.isEmpty {
        lines.append("organization: \(organizationName)")
    }
    if let jobTitle = person.jobTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !jobTitle.isEmpty {
        lines.append("job_title: \(jobTitle)")
    }
    if let notes = person.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
        lines.append("notes: \(String(notes.prefix(500)))")
    }
    return lines.joined(separator: "\n")
}

public struct ContactsReadTool: AgentTool {
    public let runtime: any AgentContactRuntime
    public var name: String { "contacts_read" }
    public var description: String { "Read governed contacts and Person Registry profiles using operations: list_people, search_people, get_person, list_contacts, search_contacts. For get_person, prefer the exact person_id from the prompt's Referenced People section; do not guess IDs from display names." }
    public var permission: AgentPermissionCapability { .readContacts }
    public var inputSchema: AgentToolInputSchema {
        .closedObject(properties: [
            "operation": .stringEnumeration(values: ["list_people", "search_people", "get_person", "resolve_person", "list_contacts", "search_contacts", "get_contact", "resolve_contact"], description: "Read operation."),
            "query": .string(description: "Person/contact query; use this for plain names that were not already resolved in Referenced People"),
            "id": .string(description: "Exact Person/contact ID. For people mentioned through Composer, use person_id from Referenced People; do not infer this from display_name")
        ], required: ["operation"])
    }
    public init(runtime: any AgentContactRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let operation = arguments.string("operation") ?? "search_people"
        switch operation {
        case "list_people":
            let people = try await runtime.listPeople()
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: summarizePeople(people, prefix: "Found \(people.count) people"), contentJSON: try ContactJSON.encode(people))
        case "search_people", "resolve_person":
            let people = try await runtime.searchPeople(query: arguments.string("query") ?? "")
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: summarizePeople(people, prefix: "Found \(people.count) people"), contentJSON: try ContactJSON.encode(people))
        case "get_person":
            guard let id = arguments.string("id") ?? arguments.string("query") else { throw AgentToolError.invalidArguments("id is required") }
            let person = try await runtime.getPerson(id: ContactID(rawValue: id))
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: summarizePerson(person), contentJSON: try ContactJSON.encode(person))
        case "list_contacts", "search_contacts", "resolve_contact":
            let records = try await runtime.search(query: arguments.string("query") ?? "")
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Found \(records.count) contacts", contentJSON: try ContactJSON.encode(records))
        case "get_contact":
            let records = try await runtime.search(query: arguments.string("query") ?? arguments.string("id") ?? "")
            let record = records.first
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: record == nil ? "Contact not found" : "Loaded contact", contentJSON: try ContactJSON.encode(record))
        default:
            throw AgentToolError.invalidArguments("Unsupported contacts_read operation: \(operation)")
        }
    }
}

public struct ContactsWriteTool: AgentTool {
    public let runtime: any AgentContactRuntime
    public var name: String { "contacts_write" }
    public var description: String { "Write governed Person Registry profiles using operations: create_person, update_person, delete_person, merge_people. For update/delete/merge, use exact person_id values from Referenced People or prior contacts_read results; never guess IDs from display names." }
    public var permission: AgentPermissionCapability { .mutateContacts }
    public var inputSchema: AgentToolInputSchema {
        .closedObject(properties: [
            "operation": .stringEnumeration(values: ["create_person", "update_person", "delete_person", "merge_people"], description: "Write operation."),
            "id": .string(description: "Exact Person ID, preferably person_id from Referenced People or contacts_read; never inferred from display name"),
            "sourceID": .string(description: "Exact merge source person ID from Referenced People or contacts_read"),
            "targetID": .string(description: "Exact merge target person ID from Referenced People or contacts_read"),
            "email": .string(description: "Email"),
            "name": .string(description: "Display name"),
            "organization": .string(description: "Organization"),
            "jobTitle": .string(description: "Job title"),
            "notes": .string(description: "Notes"),
            "approved": .boolean(description: "Explicit approval")
        ], required: ["operation", "approved"])
    }
    public init(runtime: any AgentContactRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let operation = arguments.string("operation") ?? ""
        let approved = arguments.bool("approved") ?? false
        switch operation {
        case "create_person":
            let name = arguments.string("name")
            guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentToolError.invalidArguments("name is required") }
            let email = arguments.string("email")
            let profile = PersonProfile(
                displayName: name,
                emails: email.map { [ContactEmailAddress(email: $0)] } ?? [],
                organizationName: arguments.string("organization"),
                jobTitle: arguments.string("jobTitle"),
                notes: arguments.string("notes")
            )
            let created = try await runtime.createPerson(profile, approved: approved)
            return AgentToolResult(toolCallID: context.toolCallID, toolName: self.name, contentText: "Created approved person \(created.id.rawValue)", contentJSON: try ContactJSON.encode(created))
        case "update_person":
            guard let id = arguments.string("id") else { throw AgentToolError.invalidArguments("id is required") }
            let existing = try await runtime.getPerson(id: ContactID(rawValue: id))
            guard let existing else { throw AgentToolError.invalidArguments("Unknown person") }
            var draft = PersonProfileDraft(profile: existing)
            if let name = arguments.string("name") { draft.displayName = name }
            if let organization = arguments.string("organization") { draft.organizationName = organization }
            if let jobTitle = arguments.string("jobTitle") { draft.jobTitle = jobTitle }
            if let notes = arguments.string("notes") { draft.notes = notes }
            if let email = arguments.string("email") { draft.emails = [ContactEmailAddress(email: email)] }
            let updated = try await runtime.updatePerson(id: ContactID(rawValue: id), update: draft, approved: approved)
            return AgentToolResult(toolCallID: context.toolCallID, toolName: self.name, contentText: "Updated person \(updated.id.rawValue)", contentJSON: try ContactJSON.encode(updated))
        case "delete_person":
            guard let id = arguments.string("id") else { throw AgentToolError.invalidArguments("id is required") }
            let deleted = try await runtime.deletePerson(id: ContactID(rawValue: id), approved: approved)
            return AgentToolResult(toolCallID: context.toolCallID, toolName: self.name, contentText: "Deleted person \(deleted.id.rawValue)", contentJSON: try ContactJSON.encode(deleted))
        case "merge_people":
            guard let sourceID = arguments.string("sourceID"), let targetID = arguments.string("targetID") else { throw AgentToolError.invalidArguments("sourceID and targetID are required") }
            let merged = try await runtime.mergePeople(sourceID: ContactID(rawValue: sourceID), targetID: ContactID(rawValue: targetID), approved: approved)
            return AgentToolResult(toolCallID: context.toolCallID, toolName: self.name, contentText: "Merged person \(sourceID) into \(targetID)", contentJSON: try ContactJSON.encode(merged))
        default:
            throw AgentToolError.invalidArguments("Unsupported contacts_write operation: \(operation)")
        }
    }
}

public extension AgentToolRegistry {
    mutating func registerNativeContactTools(runtime: any AgentContactRuntime) {
        register(ContactSearchTool(runtime: runtime))
        register(ContactCreateDraftTool(runtime: runtime))
        register(ContactCommitDraftTool(runtime: runtime))
    }

    mutating func registerNativeContactsAggregateTools(runtime: any AgentContactRuntime) {
        register(ContactsReadTool(runtime: runtime))
        register(ContactsWriteTool(runtime: runtime))
    }
}
