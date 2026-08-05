import Foundation
import ConnorGraphAgent
import ConnorGraphCore

private let interactiveWebSDKRequiredHint = """
index.html must load the interactive-web SDK. Without <script src="/api/v1/sdk/v1.js"></script>, the published page cannot detect login state, gate forms, collect submissions, or let Connor analyze records; visitors only see static content.

Fix it step by step:
1. Add <script src="/api/v1/sdk/v1.js"></script> inside <head>, before any other script.
2. For each submission form, set data-connor-collection="<collection>" and add a hidden _connor_honeypot input with autocomplete="off"; listen for connor:submit-start, connor:submit-success, connor:submit-error, connor:auth-required and connor:already-submitted to show prominent, polished submitting, success, failure, login-needed and already-submitted states. Once the visitor has submitted or can no longer submit (already submitted, daily/lifetime limit, or capacity full), hide or remove the fillable form and show an explicit message instead of merely disabling the submit button.
3. For login-required collections (registration, check-in, leaderboard, owner-attributed forms), check window.platform.auth.status() and offer a login button that calls window.platform.auth.login(), or let the SDK render its built-in login gate. Never draw a password input or a login form inside the page.
4. Show a visitor's own records with window.platform.collection.myRecords(name), never data.list; use collection.ranking/stats for leaderboards and collection.capacity for remaining slots; edit or remove their records with window.platform.data.updateMine/deleteMine. Note: collection.stats/capacity are aggregate data (totals, trends, group counts, numeric aggregates) and never expose raw records or identity; if the page must show aggregate statistics to visitors, set the collection's readStats to "public" or "login" (raw records stay private per readAuth).
5. After fixing the HTML, create or update the draft again (keep the exact manifestHash from interactive_web_get_draft), then publish.
"""

private let interactiveWebInlineScriptHint = """
index.html must not contain inline <script> blocks. Content pages are served with a strict Content-Security-Policy (script-src 'self') that blocks inline scripts and inline event handlers, so page JavaScript would never run and login-state rendering would silently fail. Move all page logic to the external app.js file (pass it as the javascript parameter of interactive_web_create_draft) and reference <script src="app.js"></script>. Keep submission forms in the DOM and let the SDK's data-connor-auth-required declarative login gate (or window.platform.auth.onAuthChange) handle login-state visibility; never toggle content from a login-button click handler.
"""

private let interactiveWebSDKUsageContract = """
Interactive-web guide — SDK v1 usage (window.platform):

1. SDK script: add <script src="/api/v1/sdk/v1.js"></script> inside <head> before any other script. This is the backend-provided absolute path on the same domain as the published page; copy it exactly. Never construct apiBase, projectId, or endpoint URLs yourself, and do not rewrite it as a relative path.

2. window.platform API surface:
   - data.create(name, value), data.updateMine(name, recordId, value), data.deleteMine(name, recordId), data.list(name, query)
   - forms.submit(name, formOrData)
   - auth.status(), auth.login(), auth.logout(), auth.onAuthChange(handler), auth.require(name)
   - collection.rules(name), collection.me(name), collection.myRecords(name, limit, page), collection.stats(name, query), collection.ranking(name, query), collection.capacity(name), collection.onChange(name, renderFn)

3. Forms and events: set data-connor-collection="<name>" on submission forms and add a hidden _connor_honeypot input (autocomplete="off"); the SDK submits automatically and blocks duplicate submissions. Listen for connor:submit-start, connor:submit-success, connor:submit-error, connor:auth-required and connor:already-submitted to show clear submitting, success, failure, login-needed and already-submitted states.

   Submission feedback must be prominent and polished: show a visible submitting state (disabled button with "Submitting…"), a clear success banner (highlighted block, icon, and confirmation text), and an explicit failure message with the reason and retry guidance; style feedback consistently with the rest of the page and never rely on console output or silent changes. When the visitor has already submitted or can no longer submit (already-submitted event, daily/lifetime submit limit, or capacity full — detect via connor:already-submitted, collection.me or collection.myRecords), show a clear message in place of the form ("You've already submitted", "Come back tomorrow", "No slots left") and hide or remove the fillable form instead of merely disabling its submit button.

4. Login gating: for login-required collections (anonymousCreate=false), mark the submission form or a container with data-connor-auth-required="<name>"; the SDK hides that content and shows a login guide when anonymous, then restores it when authenticated, re-evaluating on load and on auth change. You may also check window.platform.auth.status() and window.platform.collection.rules(name) yourself, or rely on the SDK's built-in gate. Never draw a password input or a login form inside the page, and never toggle content visibility from a login-button click handler.

CSP: content pages forbid inline scripts (script-src 'self'). Put all page JavaScript in the external app.js file (pass it as the javascript parameter of interactive_web_create_draft) and reference <script src="app.js"></script>; never write inline <script> blocks or inline event handlers - they are blocked and will silently not run.

5. Data reads: show a visitor's own records with window.platform.collection.myRecords(name), never data.list; use collection.ranking/stats for leaderboards and statistics, collection.capacity for remaining slots, and data.updateMine/deleteMine for edits. data.list may only be used to display all records when the collection itself is publicly readable (readAuth=public); never call it on non-public collections.

   Aggregate statistics scope: collection.stats / collection.capacity are aggregate data (totals, time series, group counts, numeric sum/avg/min/max, remaining slots) meant only for page-level totals, trends, group breakdowns, and remaining capacity. Do not use them to check whether a specific person submitted (use collection.me / collection.myRecords), do not reconstruct or infer individual records, do not group by identifying free-text fields such as names or phone numbers (the backend rejects such grouping when records are non-public), and do not aggressively paginate or scrape. When the page must show aggregate stats to visitors, set the collection's readStats to "public" or "login"; raw records still stay private per readAuth.

Pagination: records, myRecords and ranking return {items, total, page, pageSize, hasNextPage}; data.list accepts query {limit, page}. When complete coverage is required, continue with page + 1 until hasNextPage is false (or fewer than pageSize items are returned) and do not claim full coverage before then.

6. Minimal example:
   index.html:
   <form data-connor-collection="registrations" data-connor-auth-required="registrations">
     <input name="name" required>
     <input name="_connor_honeypot" autocomplete="off" hidden>
     <button type="submit">Submit</button>
   </form>
   <script src="app.js"></script>

   app.js (the javascript parameter of interactive_web_create_draft):
   window.platform.auth.onAuthChange(s => { /* optionally re-render personalized content */ });
   document.querySelector('form').addEventListener('connor:submit-success', () => {
     window.platform.collection.myRecords('registrations').then(renderMyRecords);
   });
"""

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

    public func createDraft(sessionID: String, name: String, html: String, css: String?, javascript: String?, collections: [InteractiveWebCollectionDefinition] = []) async throws -> InteractiveWebProjectStatus {
        guard (1...120).contains(name.count) else { throw AgentToolError.invalidArguments("name must contain 1 to 120 characters") }
        try validate(html, named: "index.html")
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
        if !collections.isEmpty {
            try write(
                InteractiveWebPackager.configurationJSON(collections: collections),
                named: InteractiveWebPackager.configurationFileName,
                in: project.rootURL
            )
        }
        try await store.save(project: project)
        return try status(project)
    }

	public func remoteProjects(limit: Int, page: Int = 1) async throws -> [InteractiveWebRemoteProject] {
		try await requireAPI().projects(limit: limit, page: page)
	}

	public func remoteProject(id: String) async throws -> InteractiveWebRemoteProjectDetail {
		try await requireAPI().project(id: id)
	}

	public func downloadRemoteProject(sessionID: String, remoteProjectID: String) async throws -> InteractiveWebProjectStatus {
		let api = try requireAPI()
		let remote = try await api.project(id: remoteProjectID)
		guard remote.currentDeploymentId != nil, !remote.files.isEmpty else {
			throw AgentToolError.invalidArguments("remote project has no published files")
		}
		let localID = UUID().uuidString
		let root = projectsRoot.appendingPathComponent(localID, isDirectory: true)
		try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
		do {
			for item in remote.files {
				let target = try validatedProjectFileURL(item.path, root: root)
				try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
				let data = try await api.projectFile(projectID: remote.id, path: item.path)
				guard Int64(data.count) == item.sizeBytes else { throw AgentToolError.invalidArguments("downloaded file size mismatch for \(item.path)") }
				try data.write(to: target, options: .atomic)
			}
			let manifest = try packager.package(rootURL: root)
			let expected = Dictionary(uniqueKeysWithValues: remote.files.map { ($0.path, $0.sha256.lowercased()) })
			guard manifest.files.count == remote.files.count,
				manifest.files.allSatisfy({ expected[$0.path] == $0.sha256.lowercased() }) else {
				throw AgentToolError.invalidArguments("downloaded project did not match the remote manifest")
			}
			let project = LocalInteractiveWebProject(
				id: localID,
				accountID: accountID,
				name: remote.name,
				rootURL: root,
				conversationID: sessionID,
				remoteProjectID: remote.id,
				remoteSiteID: remote.siteId,
				latestDeploymentID: remote.currentDeploymentId,
				publishedURL: remote.status == "active" ? api.publicSiteURL(siteID: remote.siteId) : nil
			)
			try await store.save(project: project)
			return try status(project)
		} catch {
			try? fileManager.removeItem(at: root)
			throw error
		}
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

    public func records(projectID: String, collection: String, limit: Int, page: Int = 1) async throws -> InteractiveWebRecordPage {
        let api = try requireAPI()
        let remoteProjectID = try await remoteProjectID(for: projectID)
        return try await api.records(projectID: remoteProjectID, collection: collection, limit: limit, page: page)
    }

    public func exportRecords(projectID: String, collection: String) async throws -> InteractiveWebExportResult {
        let api = try requireAPI()
        let remoteProjectID = try await remoteProjectID(for: projectID)
        let data = try await api.exportCSV(projectID: remoteProjectID, collection: collection)
        try fileManager.createDirectory(at: exportsRoot, withIntermediateDirectories: true)
        let target = exportsRoot.appendingPathComponent("\(projectID)-\(collection).csv")
        try data.write(to: target, options: .atomic)
        return InteractiveWebExportResult(projectID: projectID, collection: collection, fileURL: target, sizeBytes: Int64(data.count))
    }

    /// Accepts either a local draft project ID (resolved to its remote ID) or an online project ID
    /// from interactive_web_list_projects, so record queries work even without a local draft.
    private func remoteProjectID(for projectID: String) async throws -> String {
        if let project = try await store.project(id: projectID) {
            guard let remoteProjectID = project.remoteProjectID else { throw AgentToolError.invalidArguments("project has not been published") }
            return remoteProjectID
        }
        return projectID
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
		let allowed = Set(["html", "css", "js", "json", "svg"])
		guard !name.isEmpty, !name.hasPrefix("/"), !name.split(separator: "/").contains(".."), allowed.contains(URL(fileURLWithPath: name).pathExtension.lowercased()) else {
			throw AgentToolError.invalidArguments("fileName must be a relative HTML, CSS, JavaScript, JSON, or SVG path")
		}
		return name
    }

	private func validatedProjectFileURL(_ name: String, root: URL) throws -> URL {
		guard !name.isEmpty, !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else {
			throw AgentToolError.invalidArguments("remote project contains an invalid file path")
		}
		let target = root.appendingPathComponent(name).standardizedFileURL
		guard target.path.hasPrefix(root.standardizedFileURL.path + "/") else {
			throw AgentToolError.invalidArguments("remote project file escapes the user data directory")
		}
		return target
	}

    private func validate(_ content: String, named name: String) throws {
        guard Data(content.utf8).count <= 2 * 1_024 * 1_024 else {
            throw AgentToolError.invalidArguments("\(name) exceeds draft size limit")
        }
        if name == "index.html" {
            if !content.contains("sdk/v1.js") {
                throw AgentToolError.invalidArguments(interactiveWebSDKRequiredHint)
            }
            if containsInlineScript(content) {
                throw AgentToolError.invalidArguments(interactiveWebInlineScriptHint)
            }
        }
    }

    private func containsInlineScript(_ html: String) -> Bool {
        let lower = html.lowercased()
        var cursor = lower.startIndex
        while let open = lower.range(of: "<script", range: cursor..<lower.endIndex) {
            guard let close = lower.range(of: ">", range: open.upperBound..<lower.endIndex) else { break }
            let tag = lower[open.lowerBound..<close.upperBound]
            if !tag.contains("src=") { return true }
            cursor = close.upperBound
        }
        return false
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
		case sdkUsage = "interactive_web_sdk_usage"
		case listProjects = "interactive_web_list_projects"
		case getProject = "interactive_web_get_project"
		case downloadProject = "interactive_web_download_project"
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
		case .sdkUsage: .readSession
		case .createDraft, .updateDraft, .downloadProject: .createInteractiveWebDraft
		case .getDraft, .getStatus: .readSession
		case .listProjects, .getProject, .recordsSummary: .externalNetwork
        case .publish, .rollback, .setAccess, .offline, .exportRecords: .publishInteractiveWeb
        }
    }
    public var description: String {
        switch operation {
		case .sdkUsage: "Request the interactive-web guide: the complete SDK v1 specification — backend-provided script path (/api/v1/sdk/v1.js), window.platform API surface, form and event conventions, submission feedback and already-submitted states, login gating rules, data-access rules, aggregate statistics scope, and a minimal example. You MUST call this before using any interactive-web functionality; generate or edit webpage drafts strictly per the returned specification and never reconstruct page interactions from memory."
		case .listProjects: "List the signed-in user's published interactive webpage projects, one page at a time (default 50 per page, max 100). Continue with page until fewer than limit items are returned."
		case .getProject: "Read an owned online webpage project's details, deployments, file manifest, and data collection names."
		case .downloadProject: "Download an owned online webpage's current files into Connor's user data directory and register an editable local draft."
		case .createDraft: "Create a local interactive webpage draft, including persistent data collection schemas and submission rules when the page accepts registrations, feedback, votes, or other submissions. Before generating the page, call interactive_web_sdk_usage to get the complete SDK contract and example. Every page must load the backend-provided absolute SDK path /api/v1/sdk/v1.js and use window.platform instead of constructing API URLs; put all page JavaScript in the javascript parameter (app.js) and never write inline <script> blocks (CSP blocks them); drafts without the SDK script or with inline scripts are rejected with step-by-step fix guidance. The tool writes files into the app-managed user-data sandbox and does not publish anything."
        case .getDraft: "Read one source file from an app-managed interactive webpage draft. Use this before revising an existing draft so edits are based on the exact current source and manifest hash."
        case .updateDraft: "Atomically update an app-managed interactive webpage draft using exact text edits or full file replacements. Pass expectedManifestHash from interactive_web_get_draft to prevent overwriting a newer revision. Edits to index.html must keep the SDK script tag (/api/v1/sdk/v1.js)."
        case .getStatus: "Read the current local and published status of an interactive webpage project."
        case .publish: "Publish the exact current webpage revision to the internet and return its URL. Always requires native human approval; copy manifestHash exactly from create, update, or status output. Publishing rejects drafts whose index.html omits the SDK script tag."
        case .rollback: "Rollback a published webpage to a specific deployment. Always requires native human approval."
        case .setAccess: "Change who can access a published webpage. Always requires native human approval."
        case .offline: "Take a published webpage offline. Always requires native human approval."
        case .recordsSummary: "Read submitted records from a published interactive webpage collection, one page at a time (default 100 per page, max 1000). Continue with page until hasNextPage is false so all records are covered."
        case .exportRecords: "Export submitted webpage records to CSV. Always requires native human approval."
        }
    }
    public var inputSchema: AgentToolInputSchema {
        switch operation {
		case .sdkUsage:
			.closedObject(properties: [:], required: [])
		case .listProjects:
			.closedObject(properties: ["limit": .integer(description: "1 through 100"), "page": .integer(description: "1-based page number; default 1")], required: [])
		case .getProject, .downloadProject:
			.closedObject(properties: ["remoteProjectID": .string(description: "Exact online project ID")], required: ["remoteProjectID"])
        case .createDraft:
            .object(properties: [
                "name": .string(description: "Webpage name"),
                "html": .string(description: "Complete index.html"),
                "css": .string(description: "Optional stylesheet"),
                "javascript": .string(description: "Optional script"),
                "collections": .array(items: .object(properties: [
                    "name": .string(description: "Lowercase collection name"),
                    "fields": .array(items: .object(properties: [
                        "name": .string(description: "Lowercase field name"),
                        "type": .stringEnumeration(values: ["string", "number", "boolean", "enum"], description: "Stored value type"),
                        "required": .boolean(description: "Whether the value is required"),
                        "maxLength": .integer(description: "Maximum string length, or 0"),
                        "enum": .array(items: .string(description: "Allowed enum value"), description: "Allowed values for enum fields"),
                        "pattern": .string(description: "Optional RE2-compatible server-side validation pattern for string fields")
                    ], required: ["name", "type"]), description: "One to fifty validated fields"),
                    "anonymousCreate": .boolean(description: "Allow an anonymous visitor to submit; false means the visitor must be logged into a Connor account. Registration, check-in, leaderboard and owner-attributed forms must set false (login required)"),
                    "anonymousRead": .boolean(description: "Allow an anonymous visitor to read records; false keeps records visible to the owner only"),
                    "readStats": .stringEnumeration(values: ["public", "login", "owner"], description: "Aggregate statistics visibility for this collection: public = any visitor can see totals/trends/group counts/numeric aggregates; login = only logged-in visitors; owner = site owner only. Defaults to readAuth. Statistics never expose raw records or identity; only set public when the page must show aggregate stats to anonymous visitors"),
                    "submitLimit": .object(properties: [
                        "max": .integer(description: "Maximum number of submissions (1 through 10000); omit for unlimited"),
                        "window": .stringEnumeration(values: ["lifetime", "day"], description: "lifetime = once per identity overall; day = per calendar day"),
                        "scope": .stringEnumeration(values: ["account", "ip"], description: "account counts per logged-in user (requires anonymousCreate=false); ip counts per anonymous visitor")
                    ], required: ["max", "window", "scope"])
                ], required: ["name", "fields", "anonymousCreate", "anonymousRead"]), description: "Persistent data schemas and submission rules required by the page")
            ], required: ["name", "html"])
        case .getDraft:
			.closedObject(properties: ["projectID": .string(description: "Exact local project ID"), "fileName": .string(description: "Relative text source path")], required: ["projectID", "fileName"])
        case .updateDraft:
            .object(properties: [
                "projectID": .string(description: "Exact local project ID"),
                "expectedManifestHash": .string(description: "Exact manifestHash from the latest interactive_web_get_draft result"),
                "replacements": .array(items: .closedObject(properties: [
					"fileName": .string(description: "Relative text source path"),
                    "content": .string(description: "Complete replacement content")
                ], required: ["fileName", "content"]), description: "Optional complete file replacements"),
                "edits": .array(items: .closedObject(properties: [
					"fileName": .string(description: "Relative text source path"),
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
            .object(properties: ["projectID": .string(description: "Exact local project ID, or the online project ID from interactive_web_list_projects"), "collection": .string(description: "Collection name"), "limit": .integer(description: "1 through 1000"), "page": .integer(description: "1-based page number; default 1")], required: ["projectID", "collection"])
        case .exportRecords:
            .closedObject(properties: ["projectID": .string(description: "Exact local project ID, or the online project ID from interactive_web_list_projects"), "collection": .string(description: "Collection name")], required: ["projectID", "collection"])
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
        let indexSource = try await runtime.draftSource(projectID: projectID, fileName: "index.html")
        guard indexSource.content.contains("sdk/v1.js") else { throw AgentToolError.invalidArguments(interactiveWebSDKRequiredHint) }
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
		case .sdkUsage:
			status = nil
			text = interactiveWebSDKUsageContract
			json = nil
		case .listProjects:
			status = nil
			let projects = try await runtime.remoteProjects(limit: min(max(arguments.int("limit") ?? 50, 1), 100), page: max(arguments.int("page") ?? 1, 1))
			json = try encode(projects); text = "Online interactive webpage projects loaded."
		case .getProject:
			status = nil
			let project = try await runtime.remoteProject(id: requiredString("remoteProjectID", arguments))
			json = try encode(project); text = "Online interactive webpage project details loaded."
		case .downloadProject:
			status = try await runtime.downloadRemoteProject(sessionID: context.sessionID, remoteProjectID: requiredString("remoteProjectID", arguments))
			text = "Online webpage downloaded to Connor's user data directory."
        case .createDraft:
            status = try await runtime.createDraft(sessionID: context.sessionID, name: requiredString("name", arguments), html: requiredString("html", arguments), css: optionalString("css", arguments), javascript: optionalString("javascript", arguments), collections: try parseCollections(arguments))
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
            let collection = try requiredString("collection", arguments)
            let page = try await runtime.records(projectID: requiredString("projectID", arguments), collection: collection, limit: min(max(arguments.int("limit") ?? 100, 1), 1000), page: max(arguments.int("page") ?? 1, 1))
            json = try encode(page)
            let visible = page.items.prefix(50)
            let lines = visible.map { record in
                "id=\(record.id), status=\(record.status), createdAt=\(Self.isoDate(record.createdAt)), data=\(Self.compactJSON(record.data))"
            }
            let pageNote = page.hasNextPage == true ? " (hasNextPage; continue with page \(max((page.page ?? 1), 1) + 1))" : ""
            let truncated = page.items.count > visible.count ? "\n[showing first \(visible.count) of \(page.total) records]" : ""
            text = "Loaded \(page.items.count) of \(page.total) interactive webpage records for \(collection) (page \(page.page ?? 1))\(pageNote):\n" + lines.joined(separator: "\n") + truncated
        case .exportRecords:
            try requireExternalApproval(context)
            status = nil
            let result = try await runtime.exportRecords(projectID: requiredString("projectID", arguments), collection: requiredString("collection", arguments))
            json = try encode(result); text = "Interactive webpage records exported to \(result.fileURL.path)."
        }
        if let status { json = try encode(status) }
        let suffix = status.map { " projectID=\($0.projectID), revision=\($0.revision), manifestHash=\($0.manifestHash)" + ($0.publishedURL.map { ", publishedURL=[Open published webpage](\($0.absoluteString))" } ?? "") } ?? ""
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
    private func parseCollections(_ arguments: AgentToolArguments) throws -> [InteractiveWebCollectionDefinition] {
        try (arguments.array("collections") ?? []).map { value in
            guard let object = value.objectValue,
                  let name = object["name"]?.stringValue,
                  case .array(let fieldValues)? = object["fields"],
                  case .bool(let anonymousCreate)? = object["anonymousCreate"],
                  case .bool(let anonymousRead)? = object["anonymousRead"] else {
                throw AgentToolError.invalidArguments("each collection requires name, fields, anonymousCreate, and anonymousRead")
            }
            let fields = try fieldValues.map { fieldValue -> InteractiveWebCollectionField in
                guard let field = fieldValue.objectValue,
                      let fieldName = field["name"]?.stringValue,
                      let type = field["type"]?.stringValue else {
                    throw AgentToolError.invalidArguments("each collection field requires name and type")
                }
                let required: Bool
                if case .bool(let value)? = field["required"] { required = value } else { required = false }
                let maxLength: Int
                if case .int(let value)? = field["maxLength"] { maxLength = value } else { maxLength = 0 }
                let enumValues: [String]
                if case .array(let values)? = field["enum"] {
                    enumValues = try values.map {
                        guard let value = $0.stringValue else { throw AgentToolError.invalidArguments("enum values must be strings") }
                        return value
                    }
                } else {
                    enumValues = []
                }
                let pattern = field["pattern"]?.stringValue ?? ""
                return InteractiveWebCollectionField(name: fieldName, type: type, required: required, maxLength: maxLength, enum: enumValues, pattern: pattern)
            }
            let submitLimit: InteractiveWebSubmitLimit?
            if let limit = object["submitLimit"]?.objectValue,
               case .int(let max)? = limit["max"],
               case .string(let window)? = limit["window"],
               case .string(let scope)? = limit["scope"] {
                submitLimit = InteractiveWebSubmitLimit(max: max, window: window, scope: scope)
            } else {
                submitLimit = nil
            }
            let readStats = object["readStats"]?.stringValue
            return InteractiveWebCollectionDefinition(name: name, fields: fields, anonymousCreate: anonymousCreate, anonymousRead: anonymousRead, submitLimit: submitLimit, readStats: readStats)
        }
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

    private static func compactJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func isoDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
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
