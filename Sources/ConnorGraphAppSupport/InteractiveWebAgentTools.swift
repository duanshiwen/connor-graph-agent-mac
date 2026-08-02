import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public actor InteractiveWebToolRuntime {
    private let projectsRoot: URL
    private let exportsRoot: URL
    private let accountID: String
    private let store: InteractiveWebLocalStore
    private let api: InteractiveWebAPIClient?
    private let packager: InteractiveWebPackager
    private let fileManager: FileManager

    public init(
        storagePaths: AppStoragePaths,
        accountID: String,
        api: InteractiveWebAPIClient?,
        packager: InteractiveWebPackager = InteractiveWebPackager(),
        fileManager: FileManager = .default
    ) {
        let root = storagePaths.artifactsDirectory.appendingPathComponent("interactive-web", isDirectory: true)
        self.projectsRoot = root.appendingPathComponent("projects", isDirectory: true)
        self.exportsRoot = root.appendingPathComponent("exports", isDirectory: true)
        self.accountID = accountID
        self.store = InteractiveWebLocalStore(storagePaths: storagePaths)
        self.api = api
        self.packager = packager
        self.fileManager = fileManager
    }

    public func createDraft(sessionID: String, name: String, html: String, css: String?, javascript: String?) async throws -> InteractiveWebProjectStatus {
        guard (1...120).contains(name.count) else { throw AgentToolError.invalidArguments("name must contain 1 to 120 characters") }
        let project = LocalInteractiveWebProject(
            accountID: accountID,
            name: name,
            rootURL: projectsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true),
            conversationID: sessionID
        )
        try fileManager.createDirectory(at: project.rootURL, withIntermediateDirectories: true)
        try write(html, named: "index.html", in: project.rootURL)
        if let css { try write(css, named: "style.css", in: project.rootURL) }
        if let javascript { try write(javascript, named: "app.js", in: project.rootURL) }
        try await store.save(project: project)
        return try status(project)
    }

    public func draftSource(projectID: String, fileName: String) async throws -> InteractiveWebDraftSource {
        let project = try await requireProject(projectID)
        let name = try validatedDraftFileName(fileName)
        let currentStatus = try status(project)
        let target = project.rootURL.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: target.path) else {
            throw AgentToolError.invalidArguments("\(name) does not exist in this draft")
        }
        let data = try Data(contentsOf: target)
        guard data.count <= 2 * 1_024 * 1_024 else {
            throw AgentToolError.invalidArguments("\(name) exceeds draft read limit")
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw AgentToolError.invalidArguments("\(name) is not valid UTF-8 text")
        }
        return InteractiveWebDraftSource(
            projectID: project.id,
            revision: currentStatus.revision,
            manifestHash: currentStatus.manifestHash,
            fileName: name,
            content: content
        )
    }

    public func updateDraft(
        projectID: String,
        expectedManifestHash: String,
        replacements: [String: String],
        edits: [String: [(oldText: String, newText: String)]]
    ) async throws -> InteractiveWebProjectStatus {
        var project = try await requireProject(projectID)
        let currentStatus = try status(project)
        guard currentStatus.manifestHash == expectedManifestHash else {
            throw AgentToolError.invalidArguments("expectedManifestHash does not match the current draft; read the draft again before editing")
        }
        let touchedNames = Set(replacements.keys).union(edits.keys)
        guard !touchedNames.isEmpty else { throw AgentToolError.invalidArguments("at least one draft change is required") }

        var projected: [String: String] = [:]
        for rawName in touchedNames {
            let name = try validatedDraftFileName(rawName)
            if let replacement = replacements[rawName] {
                projected[name] = replacement
            } else {
                let target = project.rootURL.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: target.path) else {
                    throw AgentToolError.invalidArguments("\(name) does not exist; use a full replacement to create it")
                }
                projected[name] = try String(contentsOf: target, encoding: .utf8)
            }
            if let fileEdits = edits[rawName] {
                projected[name] = try applyingEdits(fileEdits, to: projected[name] ?? "", fileName: name)
            }
        }
        for (name, content) in projected { try validate(content, named: name) }
        try validateProjectedDraft(project: project, projected: projected)
        try commit(projected: projected, root: project.rootURL)
        project.revision = (project.revision ?? 1) + 1
        try await store.save(project: project)
        return try status(project)
    }

    public func status(projectID: String) async throws -> InteractiveWebProjectStatus {
        let project = try await requireProject(projectID)
        return try status(project)
    }

    public func publish(projectID: String, expectedManifestHash: String, accessMode: InteractiveWebAccessMode, password: String?) async throws -> InteractiveWebProjectStatus {
        let project = try await requireProject(projectID)
        let manifest = try packager.package(rootURL: project.rootURL)
        guard packager.fingerprint(manifest) == expectedManifestHash else {
            throw AgentToolError.invalidArguments("approved manifestHash no longer matches the current draft")
        }
        let api = try requireAPI()
        let published = try await api.publish(project: project, manifest: manifest)
        if let siteID = published.remoteSiteID {
            try await api.updateAccessPolicy(siteID: siteID, mode: accessMode, password: password)
        }
        try await store.save(project: published)
        return try status(published)
    }

    public func rollback(projectID: String, deploymentID: String) async throws -> InteractiveWebProjectStatus {
        let api = try requireAPI()
        var project = try await requireProject(projectID)
        guard let remoteProjectID = project.remoteProjectID else { throw AgentToolError.invalidArguments("project has not been published") }
        try await api.rollback(projectID: remoteProjectID, deploymentID: deploymentID)
        project.latestDeploymentID = deploymentID
        try await store.save(project: project)
        return try status(project)
    }

    public func setAccess(projectID: String, mode: InteractiveWebAccessMode, password: String?) async throws -> InteractiveWebProjectStatus {
        let api = try requireAPI()
        let project = try await requireProject(projectID)
        guard let siteID = project.remoteSiteID else { throw AgentToolError.invalidArguments("project has not been published") }
        try await api.updateAccessPolicy(siteID: siteID, mode: mode, password: password)
        return try status(project)
    }

    public func offline(projectID: String) async throws -> InteractiveWebProjectStatus {
        let api = try requireAPI()
        var project = try await requireProject(projectID)
        guard let siteID = project.remoteSiteID else { throw AgentToolError.invalidArguments("project has not been published") }
        try await api.offline(siteID: siteID)
        project.publishedURL = nil
        try await store.save(project: project)
        return try status(project)
    }

    public func records(projectID: String, collection: String, limit: Int) async throws -> [InteractiveWebRecordMetadata] {
        let api = try requireAPI()
        let project = try await requireProject(projectID)
        guard let remoteProjectID = project.remoteProjectID else { throw AgentToolError.invalidArguments("project has not been published") }
        return try await api.records(projectID: remoteProjectID, collection: collection, limit: limit)
    }

    public func exportRecords(projectID: String, collection: String) async throws -> InteractiveWebExportResult {
        let api = try requireAPI()
        let project = try await requireProject(projectID)
        guard let remoteProjectID = project.remoteProjectID else { throw AgentToolError.invalidArguments("project has not been published") }
        let data = try await api.exportCSV(projectID: remoteProjectID, collection: collection)
        try fileManager.createDirectory(at: exportsRoot, withIntermediateDirectories: true)
        let target = exportsRoot.appendingPathComponent("\(project.id)-\(collection).csv")
        try data.write(to: target, options: .atomic)
        return InteractiveWebExportResult(projectID: project.id, collection: collection, fileURL: target, sizeBytes: Int64(data.count))
    }

    private func requireProject(_ id: String) async throws -> LocalInteractiveWebProject {
        guard let project = try await store.project(id: id) else { throw AgentToolError.invalidArguments("interactive webpage project not found") }
        let root = project.rootURL.resolvingSymlinksInPath().standardizedFileURL
        let allowed = projectsRoot.resolvingSymlinksInPath().standardizedFileURL
        guard root.path.hasPrefix(allowed.path + "/") else { throw AgentToolError.permissionDenied("project root escapes interactive webpage sandbox") }
        return project
    }

    private func status(_ project: LocalInteractiveWebProject) throws -> InteractiveWebProjectStatus {
        let manifest = try packager.package(rootURL: project.rootURL)
        return InteractiveWebProjectStatus(
            projectID: project.id,
            name: project.name,
            rootURL: project.rootURL,
            revision: project.revision ?? 1,
            manifestHash: packager.fingerprint(manifest),
            fileCount: manifest.files.count,
            totalBytes: manifest.files.reduce(0) { $0 + $1.sizeBytes },
            remoteProjectID: project.remoteProjectID,
            remoteSiteID: project.remoteSiteID,
            latestDeploymentID: project.latestDeploymentID,
            publishedURL: project.publishedURL
        )
    }

    private func write(_ content: String, named name: String, in root: URL) throws {
        try validate(content, named: name)
        let data = Data(content.utf8)
        let target = root.appendingPathComponent(name).standardizedFileURL
        guard target.deletingLastPathComponent() == root.standardizedFileURL else { throw AgentToolError.invalidArguments("invalid draft path") }
        try data.write(to: target, options: .atomic)
    }

    private func validatedDraftFileName(_ name: String) throws -> String {
        guard ["index.html", "style.css", "app.js"].contains(name) else {
            throw AgentToolError.invalidArguments("fileName must be index.html, style.css, or app.js")
        }
        return name
    }

    private func validate(_ content: String, named name: String) throws {
        guard Data(content.utf8).count <= 2 * 1_024 * 1_024 else {
            throw AgentToolError.invalidArguments("\(name) exceeds draft size limit")
        }
    }

    private func applyingEdits(
        _ edits: [(oldText: String, newText: String)],
        to original: String,
        fileName: String
    ) throws -> String {
        var updated = original
        for (index, edit) in edits.enumerated() {
            guard !edit.oldText.isEmpty else {
                throw AgentToolError.invalidArguments("edit \(index) for \(fileName) has empty oldText")
            }
            let matches = updated.ranges(of: edit.oldText)
            guard matches.count == 1, let range = matches.first else {
                throw AgentToolError.invalidArguments("edit \(index) for \(fileName) requires oldText to occur exactly once; found \(matches.count)")
            }
            updated.replaceSubrange(range, with: edit.newText)
        }
        return updated
    }

    private func validateProjectedDraft(project: LocalInteractiveWebProject, projected: [String: String]) throws {
        let validationRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ConnorInteractiveWebValidation-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: validationRoot) }
        try fileManager.copyItem(at: project.rootURL, to: validationRoot)
        for (name, content) in projected {
            try Data(content.utf8).write(to: validationRoot.appendingPathComponent(name), options: .atomic)
        }
        _ = try packager.package(rootURL: validationRoot)
    }

    private func commit(projected: [String: String], root: URL) throws {
        let orderedNames = projected.keys.sorted()
        let originals = try Dictionary(uniqueKeysWithValues: orderedNames.map { name in
            let target = root.appendingPathComponent(name)
            return (name, fileManager.fileExists(atPath: target.path) ? try Data(contentsOf: target) : nil)
        })
        var committed: [String] = []
        do {
            for name in orderedNames {
                try Data((projected[name] ?? "").utf8).write(to: root.appendingPathComponent(name), options: .atomic)
                committed.append(name)
            }
        } catch {
            for name in committed.reversed() {
                let target = root.appendingPathComponent(name)
                if let original = originals[name] ?? nil {
                    try? original.write(to: target, options: .atomic)
                } else {
                    try? fileManager.removeItem(at: target)
                }
            }
            throw error
        }
    }

    private func requireAPI() throws -> InteractiveWebAPIClient {
        guard let api else { throw AgentToolError.permissionDenied("interactive webpage backend is unavailable") }
        return api
    }

}

public struct InteractiveWebAgentTool: AgentTool {
    public enum Operation: String, Sendable, CaseIterable {
        case createDraft = "interactive_web_create_draft"
        case getDraft = "interactive_web_get_draft"
        case updateDraft = "interactive_web_update_draft"
        case getStatus = "interactive_web_get_status"
        case publish = "interactive_web_publish"
        case rollback = "interactive_web_rollback"
        case setAccess = "interactive_web_set_access"
        case offline = "interactive_web_offline"
        case recordsSummary = "interactive_web_records_summary"
        case exportRecords = "interactive_web_export_records"
    }

    public let operation: Operation
    public let runtime: InteractiveWebToolRuntime
    public var name: String { operation.rawValue }
    public var permission: AgentPermissionCapability {
        switch operation {
        case .createDraft, .updateDraft: .createInteractiveWebDraft
        case .getDraft, .getStatus: .readSession
        case .recordsSummary: .externalNetwork
        case .publish, .rollback, .setAccess, .offline, .exportRecords: .publishInteractiveWeb
        }
    }
    public var description: String {
        switch operation {
        case .createDraft: "Create a local interactive webpage draft from complete HTML, CSS, and JavaScript generated in the current model response. The tool writes these files into the app-managed user-data sandbox; no selected workspace, local file tool, staging file, or documentation lookup is required. This does not publish anything."
        case .getDraft: "Read one source file from an app-managed interactive webpage draft. Use this before revising an existing draft so edits are based on the exact current source and manifest hash."
        case .updateDraft: "Atomically update an app-managed interactive webpage draft using exact text edits or full file replacements. Pass expectedManifestHash from interactive_web_get_draft to prevent overwriting a newer revision."
        case .getStatus: "Read the current local and published status of an interactive webpage project."
        case .publish: "Publish the exact current webpage revision to the internet and return its URL. Always requires native human approval; copy manifestHash exactly from create, update, or status output."
        case .rollback: "Rollback a published webpage to a specific deployment. Always requires native human approval."
        case .setAccess: "Change who can access a published webpage. Always requires native human approval."
        case .offline: "Take a published webpage offline. Always requires native human approval."
        case .recordsSummary: "Read recent records submitted through a published interactive webpage collection."
        case .exportRecords: "Export submitted webpage records to CSV. Always requires native human approval."
        }
    }
    public var inputSchema: AgentToolInputSchema {
        switch operation {
        case .createDraft:
            .object(properties: ["name": .string(description: "Webpage name"), "html": .string(description: "Complete index.html"), "css": .string(description: "Optional stylesheet"), "javascript": .string(description: "Optional script")], required: ["name", "html"])
        case .getDraft:
            .closedObject(properties: ["projectID": .string(description: "Exact local project ID"), "fileName": .stringEnumeration(values: ["index.html", "style.css", "app.js"], description: "Draft source file to read")], required: ["projectID", "fileName"])
        case .updateDraft:
            .object(properties: [
                "projectID": .string(description: "Exact local project ID"),
                "expectedManifestHash": .string(description: "Exact manifestHash from the latest interactive_web_get_draft result"),
                "replacements": .array(items: .closedObject(properties: [
                    "fileName": .stringEnumeration(values: ["index.html", "style.css", "app.js"], description: "Draft file to replace"),
                    "content": .string(description: "Complete replacement content")
                ], required: ["fileName", "content"]), description: "Optional complete file replacements"),
                "edits": .array(items: .closedObject(properties: [
                    "fileName": .stringEnumeration(values: ["index.html", "style.css", "app.js"], description: "Existing draft file to edit"),
                    "oldText": .string(description: "Exact text that must occur once"),
                    "newText": .string(description: "Replacement text")
                ], required: ["fileName", "oldText", "newText"]), description: "Optional ordered exact text replacements")
            ], required: ["projectID", "expectedManifestHash"])
        case .getStatus, .offline:
            .closedObject(properties: ["projectID": .string(description: "Exact local project ID")], required: ["projectID"])
        case .publish:
            .object(properties: ["projectID": .string(description: "Exact local project ID"), "manifestHash": .string(description: "Exact 64-character hash from the latest local status"), "accessMode": .stringEnumeration(values: ["public", "password", "private"], description: "Who can access the site"), "password": .string(description: "Required only for password access")], required: ["projectID", "manifestHash", "accessMode"])
        case .rollback:
            .closedObject(properties: ["projectID": .string(description: "Exact local project ID"), "deploymentID": .string(description: "Target deployment ID")], required: ["projectID", "deploymentID"])
        case .setAccess:
            .object(properties: ["projectID": .string(description: "Exact local project ID"), "accessMode": .stringEnumeration(values: ["public", "password", "private"], description: "Who can access the site"), "password": .string(description: "Required only for password access")], required: ["projectID", "accessMode"])
        case .recordsSummary:
            .object(properties: ["projectID": .string(description: "Exact local project ID"), "collection": .string(description: "Collection name"), "limit": .integer(description: "1 through 1000")], required: ["projectID", "collection"])
        case .exportRecords:
            .closedObject(properties: ["projectID": .string(description: "Exact local project ID"), "collection": .string(description: "Collection name")], required: ["projectID", "collection"])
        }
    }

    public init(operation: Operation, runtime: InteractiveWebToolRuntime) { self.operation = operation; self.runtime = runtime }

    public func preflight(call: AgentToolCall, context: AgentToolExecutionContext) async throws {
        guard operation == .publish else { return }
        let arguments = try AgentToolArguments(json: call.argumentsJSON)
        let projectID = try requiredString("projectID", arguments)
        let expectedHash = try requiredString("manifestHash", arguments)
        let status = try await runtime.status(projectID: projectID)
        guard status.manifestHash == expectedHash else { throw AgentToolError.invalidArguments("manifestHash does not match the current draft") }
    }

    public func approvalPayloadJSON(for call: AgentToolCall, context: AgentToolExecutionContext) async -> String {
        guard let arguments = try? AgentToolArguments(json: call.argumentsJSON),
              let projectID = arguments.string("projectID"),
              let status = try? await runtime.status(projectID: projectID)
        else { return call.argumentsJSON }
        var payload: [String: Any] = [
            "projectID": status.projectID,
            "siteName": status.name,
            "revision": status.revision,
            "manifestHash": status.manifestHash,
            "fileCount": status.fileCount,
            "totalBytes": status.totalBytes,
            "operation": operation.rawValue
        ]
        if let accessMode = arguments.string("accessMode") { payload["accessMode"] = accessMode }
        if let deploymentID = arguments.string("deploymentID") { payload["deploymentID"] = deploymentID }
        if let collection = arguments.string("collection") { payload["collection"] = collection }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return call.argumentsJSON }
        return String(decoding: data, as: UTF8.self)
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let status: InteractiveWebProjectStatus?
        let text: String
        var json: String?
        switch operation {
        case .createDraft:
            status = try await runtime.createDraft(sessionID: context.sessionID, name: requiredString("name", arguments), html: requiredString("html", arguments), css: optionalString("css", arguments), javascript: optionalString("javascript", arguments))
            text = "Local webpage draft created."
        case .getDraft:
            status = nil
            let source = try await runtime.draftSource(projectID: requiredString("projectID", arguments), fileName: requiredString("fileName", arguments))
            json = try encode(source)
            text = "Loaded \(source.fileName) from draft projectID=\(source.projectID), revision=\(source.revision), manifestHash=\(source.manifestHash)."
        case .updateDraft:
            let replacements = try parseReplacements(arguments)
            let edits = try parseEdits(arguments)
            status = try await runtime.updateDraft(
                projectID: requiredString("projectID", arguments),
                expectedManifestHash: requiredString("expectedManifestHash", arguments),
                replacements: replacements,
                edits: edits
            )
            text = "Local webpage draft updated."
        case .getStatus:
            status = try await runtime.status(projectID: requiredString("projectID", arguments)); text = "Interactive webpage status loaded."
        case .publish:
            try requireExternalApproval(context)
            let mode = try accessMode(arguments)
            let password = optionalString("password", arguments)
            if mode == .password && password == nil { throw AgentToolError.invalidArguments("password is required for password access") }
            status = try await runtime.publish(projectID: requiredString("projectID", arguments), expectedManifestHash: requiredString("manifestHash", arguments), accessMode: mode, password: password)
            text = "Approved webpage revision published."
        case .rollback:
            try requireExternalApproval(context)
            status = try await runtime.rollback(projectID: requiredString("projectID", arguments), deploymentID: requiredString("deploymentID", arguments)); text = "Published webpage rolled back."
        case .setAccess:
            try requireExternalApproval(context)
            let mode = try accessMode(arguments), password = optionalString("password", arguments)
            if mode == .password && password == nil { throw AgentToolError.invalidArguments("password is required for password access") }
            status = try await runtime.setAccess(projectID: requiredString("projectID", arguments), mode: mode, password: password); text = "Published webpage access updated."
        case .offline:
            try requireExternalApproval(context)
            status = try await runtime.offline(projectID: requiredString("projectID", arguments)); text = "Published webpage is offline."
        case .recordsSummary:
            status = nil
            let records = try await runtime.records(projectID: requiredString("projectID", arguments), collection: requiredString("collection", arguments), limit: min(max(arguments.int("limit") ?? 100, 1), 1000))
            json = try encode(records); text = "Interactive webpage records loaded."
        case .exportRecords:
            try requireExternalApproval(context)
            status = nil
            let result = try await runtime.exportRecords(projectID: requiredString("projectID", arguments), collection: requiredString("collection", arguments))
            json = try encode(result); text = "Interactive webpage records exported to \(result.fileURL.path)."
        }
        if let status { json = try encode(status) }
        let suffix = status.map { " projectID=\($0.projectID), revision=\($0.revision), manifestHash=\($0.manifestHash)" + ($0.publishedURL.map { ", url=\($0.absoluteString)" } ?? "") } ?? ""
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: text + suffix, contentJSON: json)
    }

    private func requiredString(_ key: String, _ arguments: AgentToolArguments) throws -> String {
        guard let value = optionalString(key, arguments) else { throw AgentToolError.invalidArguments("\(key) is required") }
        return value
    }
    private func optionalString(_ key: String, _ arguments: AgentToolArguments) -> String? {
        arguments.string(key)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
    private func accessMode(_ arguments: AgentToolArguments) throws -> InteractiveWebAccessMode {
        guard let raw = optionalString("accessMode", arguments), let mode = InteractiveWebAccessMode(rawValue: raw) else { throw AgentToolError.invalidArguments("accessMode must be public, password, or private") }
        return mode
    }
    private func requireExternalApproval(_ context: AgentToolExecutionContext) throws {
        guard context.approvedCapabilities.contains(.publishInteractiveWeb) else { throw AgentToolError.permissionDenied("interactive webpage external write requires native approval") }
    }
    private func parseReplacements(_ arguments: AgentToolArguments) throws -> [String: String] {
        var replacements: [String: String] = [:]
        for value in arguments.array("replacements") ?? [] {
            guard let object = value.objectValue,
                  let fileName = object["fileName"]?.stringValue,
                  let content = object["content"]?.stringValue else {
                throw AgentToolError.invalidArguments("each replacement requires fileName and content")
            }
            guard replacements[fileName] == nil else { throw AgentToolError.invalidArguments("duplicate replacement for \(fileName)") }
            replacements[fileName] = content
        }
        return replacements
    }
    private func parseEdits(_ arguments: AgentToolArguments) throws -> [String: [(oldText: String, newText: String)]] {
        var edits: [String: [(oldText: String, newText: String)]] = [:]
        for value in arguments.array("edits") ?? [] {
            guard let object = value.objectValue,
                  let fileName = object["fileName"]?.stringValue,
                  let oldText = object["oldText"]?.stringValue,
                  let newText = object["newText"]?.stringValue else {
                throw AgentToolError.invalidArguments("each edit requires fileName, oldText, and newText")
            }
            edits[fileName, default: []].append((oldText, newText))
        }
        return edits
    }
    private func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

public extension AgentToolRegistry {
    mutating func registerInteractiveWebTools(runtime: InteractiveWebToolRuntime) {
        for operation in InteractiveWebAgentTool.Operation.allCases {
            register(InteractiveWebAgentTool(operation: operation, runtime: runtime))
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    func ranges(of substring: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var searchStart = startIndex
        while searchStart < endIndex, let range = range(of: substring, range: searchStart..<endIndex) {
            result.append(range)
            searchStart = range.upperBound
        }
        return result
    }
}
