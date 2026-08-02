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

    public func updateDraft(projectID: String, html: String?, css: String?, javascript: String?) async throws -> InteractiveWebProjectStatus {
        var project = try await requireProject(projectID)
        if let html { try write(html, named: "index.html", in: project.rootURL) }
        if let css { try write(css, named: "style.css", in: project.rootURL) }
        if let javascript { try write(javascript, named: "app.js", in: project.rootURL) }
        project.revision = (project.revision ?? 1) + 1
        try await store.save(project: project)
        return try status(project)
    }

    public func status(projectID: String) async throws -> InteractiveWebProjectStatus {
        let project = try await requireProject(projectID)
        return try status(project)
    }

    public func publish(projectID: String, expectedManifestHash: String, accessMode: InteractiveWebAccessMode, password: String?) async throws -> InteractiveWebProjectStatus {
        let api = try requireAPI()
        let project = try await requireProject(projectID)
        let manifest = try packager.package(rootURL: project.rootURL)
        guard packager.fingerprint(manifest) == expectedManifestHash else {
            throw AgentToolError.invalidArguments("approved manifestHash no longer matches the current draft")
        }
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
        let data = Data(content.utf8)
        guard data.count <= 2 * 1_024 * 1_024 else { throw AgentToolError.invalidArguments("\(name) exceeds draft size limit") }
        let target = root.appendingPathComponent(name).standardizedFileURL
        guard target.deletingLastPathComponent() == root.standardizedFileURL else { throw AgentToolError.invalidArguments("invalid draft path") }
        try data.write(to: target, options: .atomic)
    }

    private func requireAPI() throws -> InteractiveWebAPIClient {
        guard let api else { throw AgentToolError.permissionDenied("interactive webpage backend is unavailable") }
        return api
    }
}

public struct InteractiveWebAgentTool: AgentTool {
    public enum Operation: String, Sendable, CaseIterable {
        case createDraft = "interactive_web_create_draft"
        case updateDraft = "interactive_web_update_draft"
        case preview = "interactive_web_preview"
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
        case .createDraft, .updateDraft: .writeWorkspaceFile
        case .preview, .getStatus: .readSession
        case .recordsSummary: .externalNetwork
        case .publish, .rollback, .setAccess, .offline, .exportRecords: .publishInteractiveWeb
        }
    }
    public var description: String {
        switch operation {
        case .createDraft: "Create a local interactive webpage draft in the app sandbox. This does not publish anything."
        case .updateDraft: "Update an existing local interactive webpage draft. This does not publish anything."
        case .preview: "Return the current local preview target and exact artifact hash for the secure preview runtime."
        case .getStatus: "Read the current local and published status of an interactive webpage project."
        case .publish: "Publish the exact reviewed webpage revision to the internet. Always requires native human approval; copy manifestHash exactly from a prior tool result."
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
        case .updateDraft:
            .object(properties: ["projectID": .string(description: "Exact local project ID"), "html": .string(description: "Replacement index.html"), "css": .string(description: "Replacement stylesheet"), "javascript": .string(description: "Replacement script")], required: ["projectID"])
        case .preview, .getStatus, .offline:
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
        case .updateDraft:
            let html = optionalString("html", arguments), css = optionalString("css", arguments), javascript = optionalString("javascript", arguments)
            guard html != nil || css != nil || javascript != nil else { throw AgentToolError.invalidArguments("at least one draft file is required") }
            status = try await runtime.updateDraft(projectID: requiredString("projectID", arguments), html: html, css: css, javascript: javascript)
            text = "Local webpage draft updated."
        case .preview:
            status = try await runtime.status(projectID: requiredString("projectID", arguments)); text = "Secure local preview is ready."
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
}
