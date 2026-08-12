import Foundation
import CryptoKit
import ConnorGraphAgent
import ConnorGraphCore

private let interactiveWebSDKRequiredHint = """
index.html must load the interactive-web SDK. Without <script src="/api/v1/sdk/v1.js"></script>, the published page cannot detect login state, gate forms, collect submissions, or let Connor analyze records; visitors only see static content.

Fix it step by step:
1. Add <script src="/api/v1/sdk/v1.js"></script> inside <head>, before any other script.
2. For each submission form, set data-connor-collection="<collection>" and add a hidden _connor_honeypot input with autocomplete="off"; listen for connor:submit-start, connor:submit-success, connor:submit-error, connor:auth-required and connor:already-submitted to show prominent, polished submitting, success, failure, login-needed and already-submitted states. Once the visitor has submitted or can no longer submit (already submitted, daily/lifetime limit, or capacity full), hide or remove the fillable form and show an explicit message instead of merely disabling the submit button.
3. For login-required collections (registration, check-in, leaderboard, owner-attributed forms), check window.platform.auth.status() and offer a login button that calls window.platform.auth.login(), or let the SDK render its built-in login gate. Never draw a password input or a login form inside the page.
4. Show a visitor's own records with window.platform.collection.myRecords(name), never data.list; use collection.ranking/stats for leaderboards and collection.capacity for remaining slots; edit or remove their records with window.platform.data.updateMine/deleteMine. Note: collection.stats/capacity are aggregate data (totals, trends, group counts, numeric aggregates) and never expose raw records or identity; if the page must show aggregate statistics to visitors, set the collection's readStats to "public" or "login" (raw records stay private per readAuth).
5. After fixing the HTML, create the draft again with the corrected page (interactive_web_create_draft), then publish.
"""

private let interactiveWebInlineScriptHint = """
index.html must not contain inline <script> blocks. Content pages are served with a strict Content-Security-Policy (script-src 'self') that blocks inline scripts and inline event handlers, so page JavaScript would never run and login-state rendering would silently fail. Move all page logic to the external app.js file (pass it as the javascript parameter of interactive_web_create_draft) and reference <script src="app.js"></script>. Keep submission forms in the DOM and let the SDK's data-connor-auth-required declarative login gate (or window.platform.auth.onAuthChange) handle login-state visibility; never toggle content from a login-button click handler.
"""

private let interactiveWebSDKUsageContract = """
Interactive-web guide — SDK v1 usage (window.platform):

0. Create and update use ONE tool — interactive_web_create_draft:
   - Before any create or update, you MUST have obtained this guide in the current session via interactive_web_sdk_usage — updates often happen in a separate session, so never skip the guide and never reconstruct the workflow from memory.
   - Create: omit projectID and pass the complete name, html (required), css, javascript, and collections.
   - Update: first read EVERY current file with interactive_web_get_draft (large files are paginated: continue with offset=nextOffset until the whole file is read).
   - Targeted edit: call interactive_web_edit_draft on the same projectID with fileName and either oldText+newText (exact text replacement; an empty newText deletes the text) or content (whole-file replacement). For very large files, write content in chunks with offset (start at 0, continue with offset=nextOffset from each result) and set final=true on the last chunk. The result reports the changed file with a plain-text unified diff, before/after hashes, offset/nextOffset, and the new manifestHash — verify the diff matches the request before publishing.
   - Full rewrite: alternatively call interactive_web_create_draft with the SAME projectID and the full edited files; files you do not pass (for example css) stay unchanged.
   - Publish the same projectID afterwards: the URL and collected data stay with the project. Never recreate a project merely to change it, and never rewrite an existing page from memory.
   - Per-file size limit is 20 MB (20480 KB). Files larger than that are rejected.
   - Content must be delivered complete: never compress, simplify, or cut page features to fit a shorter output. If the complete html, css, or javascript exceeds what you can emit in one response, do NOT shorten it — write it in chunks from the very start with interactive_web_create_draft: pass fileName (default index.html), content (the current chunk), offset (default 0) and final (default false); the first call creates the project and writes chunk 1, continue with offset=nextOffset from each result on the SAME projectID, and set final=true on the last chunk for each file (index.html, style.css, app.js). Chunks are concatenated locally in exact order, never summarized or paraphrased. A draft is NOT created successfully until every chunked file has final=true: interactive_web_get_status reports incompleteWrites and interactive_web_publish rejects drafts with incomplete writes.

1. SDK script: add <script src="/api/v1/sdk/v1.js"></script> inside <head> before any other script. This is the backend-provided absolute path on the same domain as the published page; copy it exactly. Never construct apiBase, projectId, or endpoint URLs yourself, and do not rewrite it as a relative path.

   Stylesheet link check: if you pass CSS through the css parameter (saved as style.css), index.html MUST link it inside <head> with <link rel="stylesheet" href="style.css">. Before creating or updating the draft, double-check that the link tag is actually present in the returned index.html — a missing or mistyped stylesheet link is the most common reason a page publishes without its styles. The runtime also auto-checks: when style.css exists but index.html does not link it, the missing <link> is injected into <head> automatically and reported as a "css-link-injected" change — still link it yourself in the source you generate, and do not rely on the auto-fix.

   Native control height consistency: text inputs (input[type=text]), textareas, and selects (select) have different native heights across browsers/OSes, so side-by-side form controls end up misaligned. Set the same height on input, select, textarea, and button (for example height + box-sizing: border-box, or consistent padding/border/font-size), keep the same font-size on select and input (some browsers scale selects below 16px), and use appearance: none to fully style selects when needed so all form controls align visually.

2. window.platform API surface:
   - data.create(name, value), data.updateMine(name, recordId, value), data.deleteMine(name, recordId), data.list(name, query)
   - forms.submit(name, formOrData)
   - auth.status(), auth.login(), auth.logout(), auth.onAuthChange(handler), auth.require(name)
   - collection.rules(name), collection.me(name), collection.myRecords(name, limit, page), collection.stats(name, query), collection.ranking(name, query), collection.capacity(name), collection.onChange(name, renderFn)
   - links.open(url) — open an external URL in a new tab/window (only http/https accepted)

   External links (new window/tab): published pages run inside a sandboxed iframe, so a raw target="_blank" or window.open() cannot open a new window by itself. The SDK intercepts clicks on <a target="_blank"> and <a data-connor-external> anchors and opens them in a new tab/window; you may also call window.platform.link.open("https://...") from app.js for programmatic opens. Only http/https URLs are accepted; never use javascript: URLs.

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

    /// 统一的「下载全部文件 → 修改 → 传回」入口：
    /// - projectID 为空：新建项目（原来行为）
    /// - projectID 非空：把传入的完整文件写回同一项目（更新），未传入的 css/js 保持不变
    /// 返回状态 + 本次实际变更的文本 diff，供模型核对。
    public func createDraft(
        sessionID: String,
        name: String,
        html: String,
        css: String?,
        javascript: String?,
        collections: [InteractiveWebCollectionDefinition] = [],
        projectID: String? = nil,
        fileName: String? = nil,
        content: String? = nil,
        offset: Int = 0,
        final: Bool = false
    ) async throws -> InteractiveWebDraftSaveResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        var project: LocalInteractiveWebProject
        if let projectID {
            project = try await requireProject(projectID)
            if !trimmedName.isEmpty, project.name != trimmedName { project.name = trimmedName }
        } else {
            guard (1...120).contains(trimmedName.count) else { throw AgentToolError.invalidArguments("name must contain 1 to 120 characters") }
            project = LocalInteractiveWebProject(
                accountID: accountID,
                name: trimmedName,
                rootURL: projectsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true),
                conversationID: sessionID
            )
            try fileManager.createDirectory(at: project.rootURL, withIntermediateDirectories: true)
        }

        let root = project.rootURL

        // 分块创建/续写：一次只写一个文件的当前块，在本地拼接；final=true 才算该文件写完。
        // 未 final 完成的文件会记入 incompleteWrites，草稿不算创建成功，publish 会拒绝。
        if let content {
            let chunkFileName = try validatedDraftFileName(fileName ?? "index.html")
            let target = root.appendingPathComponent(chunkFileName)
            let exists = fileManager.fileExists(atPath: target.path)
            guard exists || offset == 0 else {
                throw AgentToolError.invalidArguments("\(chunkFileName) does not exist yet; the first chunk must start at offset 0")
            }
            let before = exists ? (try? String(contentsOf: target, encoding: .utf8)) ?? "" : ""
            let after: String
            if exists {
                let start = max(offset, 0)
                let startIndex = before.index(before.startIndex, offsetBy: min(start, before.count))
                let replacedEnd = before.index(startIndex, offsetBy: min(content.count, before.count - min(start, before.count)))
                var replaced = before.replacingCharacters(in: startIndex..<replacedEnd, with: content)
                if final {
                    replaced = String(replaced.prefix(min(start + content.count, replaced.count)))
                }
                after = replaced
            } else {
                after = content
            }
            if final {
                try validate(after, named: chunkFileName)
            }
            let beforeHash = exists ? Self.sha256(before) : ""
            let afterHash = Self.sha256(after)
            try Data(after.utf8).write(to: target, options: .atomic)
            var incomplete = project.incompleteWrites ?? []
            if final {
                incomplete.removeAll { $0 == chunkFileName }
            } else if !incomplete.contains(chunkFileName) {
                incomplete.append(chunkFileName)
            }
            project.incompleteWrites = incomplete
            project.revision = (project.revision ?? 1) + 1
            try await store.save(project: project)
            var chunkChanges = [InteractiveWebDraftFileChange(
                fileName: chunkFileName,
                operation: exists ? "chunk-appended" : "created",
                beforeHash: beforeHash,
                afterHash: afterHash,
                beforeSizeBytes: before.utf8.count,
                afterSizeBytes: after.utf8.count,
                diff: Self.unifiedDiff(before: before, after: after, filePath: chunkFileName)
            )]
            if final, let cssLinkChange = try ensureCssLinked(in: root) {
                chunkChanges.append(cssLinkChange)
            }
            return InteractiveWebDraftSaveResult(
                status: try status(project),
                changes: chunkChanges,
                offset: max(offset, 0),
                nextOffset: final ? nil : (max(offset, 0) + content.count)
            )
        }

        // 完整模式：一次写入完整 html/css/js（原行为）。
        guard !html.isEmpty else { throw AgentToolError.invalidArguments("html is required when not writing in chunks") }
        try validate(html, named: "index.html")

        var changes: [InteractiveWebDraftFileChange] = []
        changes.append(contentsOf: try saveFile(named: "index.html", content: html, in: root))
        if let css {
            changes.append(contentsOf: try saveFile(named: "style.css", content: css, in: root))
        }
        if let javascript {
            changes.append(contentsOf: try saveFile(named: "app.js", content: javascript, in: root))
        }
        if !collections.isEmpty {
            changes.append(contentsOf: try saveFile(
                named: InteractiveWebPackager.configurationFileName,
                content: InteractiveWebPackager.configurationJSON(collections: collections),
                in: root
            ))
        }
        // 样式链接兜底：本次提供了 css 或项目里已有 style.css 时，index.html 必须链接它；
        // 缺失则自动注入，并以 css-link-injected 变更报告给模型。
        if let cssLinkChange = try ensureCssLinked(in: root) {
            changes.append(cssLinkChange)
        }
        // 完整写入的文件视为已完成，清除未完成标记
        var incomplete = project.incompleteWrites ?? []
        for name in ["index.html", "style.css", "app.js"] where fileManager.fileExists(atPath: root.appendingPathComponent(name).path) {
            incomplete.removeAll { $0 == name }
        }
        project.incompleteWrites = incomplete
        if projectID != nil {
            project.revision = (project.revision ?? 1) + 1
        }
        try await store.save(project: project)
        return InteractiveWebDraftSaveResult(status: try status(project), changes: changes)
    }

    /// 草稿编辑：支持两种模式（二选一）——
    /// - 精确文本替换：oldText + newText（newText 传空 = 删除）
    /// - 整文件替换：content（可带游标分块写入，offset 为 0 起始字符位置，final 标记最后一块并截断旧尾部）
    /// 不整页重建、不创建新项目；返回文本 diff 与新的 manifestHash 供模型核对。
    public func editDraft(
        projectID: String,
        fileName: String,
        oldText: String?,
        newText: String?,
        content: String?,
        offset: Int = 0,
        final: Bool = false
    ) async throws -> InteractiveWebDraftEditResult {
        var project = try await requireProject(projectID)
        let name = try validatedDraftFileName(fileName)
        let currentStatus = try status(project)
        let target = project.rootURL.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: target.path) else {
            throw AgentToolError.invalidArguments("\(name) does not exist in this draft. Available files: \(currentStatus.fileNames.joined(separator: ", "))")
        }
        let before = try String(contentsOf: target, encoding: .utf8)
        let after: String
        let appliedOffset: Int
        let nextOffset: Int?
        if let content {
            let start = max(offset, 0)
            let startIndex = before.index(before.startIndex, offsetBy: min(start, before.count))
            let replacedEnd = before.index(startIndex, offsetBy: min(content.count, before.count - min(start, before.count)))
            var replaced = before.replacingCharacters(in: startIndex..<replacedEnd, with: content)
            if final {
                let keep = min(start + content.count, replaced.count)
                replaced = String(replaced.prefix(keep))
            }
            after = replaced
            appliedOffset = start
            nextOffset = start + content.count
            if final {
                try validate(after, named: name)
            }
        } else if let oldText {
            guard !oldText.isEmpty else { throw AgentToolError.invalidArguments("oldText must not be empty") }
            let matches = before.ranges(of: oldText)
            guard matches.count == 1, let range = matches.first else {
                throw AgentToolError.invalidArguments("oldText must occur exactly once in \(name); found \(matches.count). Read the current file with interactive_web_get_draft and retry with the exact text.")
            }
            after = before.replacingCharacters(in: range, with: newText ?? "")
            appliedOffset = 0
            nextOffset = nil
            try validate(after, named: name)
        } else {
            throw AgentToolError.invalidArguments("edit requires either oldText+newText (targeted edit) or content (full-file replacement)")
        }
        let changed = after != before
        if !changed {
            // 目标状态已存在（分块写入的中间块相同，或 oldText/newText 本就相等）：
            // 视为幂等成功——不写盘、不升版本，继续返回游标/结果，而不是误报失败。
            let unchangedStatus = try status(project)
            return InteractiveWebDraftEditResult(
                status: unchangedStatus,
                fileName: name,
                beforeHash: Self.sha256(before),
                afterHash: Self.sha256(before),
                beforeSizeBytes: before.utf8.count,
                afterSizeBytes: before.utf8.count,
                diff: "",
                offset: appliedOffset,
                nextOffset: nextOffset,
                resultTotalCharacters: before.count
            )
        }
        var finalAfter = after
        if name == "index.html",
           fileManager.fileExists(atPath: target.deletingLastPathComponent().appendingPathComponent("style.css").path),
           !hasStylesheetLink(finalAfter) {
            finalAfter = injectStylesheetLink(finalAfter)
        }
        let originalData = try Data(contentsOf: target)
        do {
            try Data(finalAfter.utf8).write(to: target, options: .atomic)
        } catch {
            try? originalData.write(to: target, options: .atomic)
            throw error
        }
        if name == "style.css" {
            // 补上 style.css 后，若 index.html 尚未链接，自动注入（不额外报变更，避免编辑结果语义混乱）。
            _ = try ensureCssLinked(in: target.deletingLastPathComponent())
        }
        project.revision = (project.revision ?? 1) + 1
        try await store.save(project: project)
        let afterStatus = try status(project)
        return InteractiveWebDraftEditResult(
            status: afterStatus,
            fileName: name,
            beforeHash: Self.sha256(before),
            afterHash: Self.sha256(finalAfter),
            beforeSizeBytes: before.utf8.count,
            afterSizeBytes: finalAfter.utf8.count,
            diff: Self.unifiedDiff(before: before, after: finalAfter, filePath: name),
            offset: appliedOffset,
            nextOffset: nextOffset,
            resultTotalCharacters: finalAfter.count
        )
    }

	public func remoteProjects(limit: Int, page: Int = 1) async throws -> [InteractiveWebRemoteProject] {
		let api = try requireAPI()
		let projects = try await api.projects(limit: limit, page: page)
		return projects.map { project in
			var project = project
			if project.publishedURL == nil, !project.siteId.isEmpty {
				project.publishedURL = api.publicSiteURL(siteID: project.siteId).absoluteString
			}
			return project
		}
	}

	public func remoteProject(id: String) async throws -> InteractiveWebRemoteProjectDetail {
		try await requireAPI().project(id: id)
	}

	public func downloadRemoteProject(sessionID: String, remoteProjectID: String) async throws -> InteractiveWebProjectStatus {
		let api = try requireAPI()
		let remote = try await api.project(id: remoteProjectID)
		guard remote.currentDeploymentId != nil, !remote.files.isEmpty else {
			throw AgentToolError.invalidArguments("remote project \(remoteProjectID) has no published files. Only published webpages can be downloaded; use interactive_web_create_draft to build a new local draft, or publish this project first.")
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

    public func draftSource(projectID: String, fileName: String, offset: Int = 0, limit: Int? = nil) async throws -> InteractiveWebDraftSource {
        let project = try await requireProject(projectID)
        let name = try validatedDraftFileName(fileName)
        let currentStatus = try status(project)
        let target = project.rootURL.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: target.path) else {
            throw AgentToolError.invalidArguments("\(name) does not exist in this draft. Available files in this draft: \(currentStatus.fileNames.joined(separator: ", "))")
        }
        let data = try Data(contentsOf: target)
        guard data.count <= 20 * 1_024 * 1_024 else {
            throw AgentToolError.invalidArguments("\(name) exceeds draft read limit")
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw AgentToolError.invalidArguments("\(name) is not valid UTF-8 text")
        }
        let totalCharacters = content.count
        let windowOffset = max(offset, 0)
        let windowLimit = min(max(limit ?? 100_000, 0), 1_000_000)
        let start = min(windowOffset, totalCharacters)
        let end = min(start + windowLimit, totalCharacters)
        let slice = String(content[content.index(content.startIndex, offsetBy: start)..<content.index(content.startIndex, offsetBy: end)])
        let remainingCharacters = max(0, totalCharacters - end)
        let estimatedRemainingCalls = remainingCharacters == 0
            ? 0
            : max(1, Int((Double(remainingCharacters) / Double(max(windowLimit, 1))).rounded(.up)))
        return InteractiveWebDraftSource(
            projectID: project.id,
            revision: currentStatus.revision,
            manifestHash: currentStatus.manifestHash,
            fileName: name,
            content: slice,
            availableFiles: currentStatus.fileNames,
            offset: start,
            limit: windowLimit,
            totalCharacters: totalCharacters,
            truncated: end < totalCharacters,
            nextOffset: end < totalCharacters ? end : nil,
            remainingCharacters: remainingCharacters,
            estimatedRemainingCalls: estimatedRemainingCalls
        )
    }

    public func status(projectID: String) async throws -> InteractiveWebProjectStatus {
        let project = try await requireProject(projectID)
        return try status(project)
    }

    public func publish(projectID: String, expectedManifestHash: String, accessMode: InteractiveWebAccessMode, password: String?) async throws -> InteractiveWebProjectStatus {
        let project = try await requireProject(projectID)
        guard (project.incompleteWrites ?? []).isEmpty else {
            throw AgentToolError.invalidArguments("draft is not complete: chunked writes for \((project.incompleteWrites ?? []).joined(separator: ", ")) have not finished (missing final=true). Continue writing the remaining chunks with interactive_web_create_draft or interactive_web_edit_draft before publishing.")
        }
        let manifest = try packager.package(rootURL: project.rootURL)
        let currentManifestHash = packager.fingerprint(manifest)
        guard currentManifestHash == expectedManifestHash else {
            throw AgentToolError.invalidArguments("approved manifestHash no longer matches the current draft; read the draft again before editing. Current manifestHash=\(currentManifestHash)")
        }
        let api = try requireAPI()
        if project.remoteProjectID == nil {
            // 防“改版误建新链接”：本地 draft 还没有对应线上项目，但账号下已有同名已发布网页时，
            // 提示先下载原项目再修改，而不是静默创建一个新项目/新链接。
            let remoteProjects = (try? await api.projects(limit: 100)) ?? []
            if let existing = remoteProjects.first(where: { $0.name == project.name && $0.status == "active" }) {
                let url = existing.publishedURL ?? api.publicSiteURL(siteID: existing.siteId).absoluteString
                throw AgentToolError.invalidArguments(
                    "检测到同名已发布网页“\(existing.name)”（\(url)）。如果是要修改这个已发布的网页，请先调用 interactive_web_download_project(remoteProjectID: \"\(existing.id)\") 下载原项目，修改后用返回的同一 projectID 发布（链接保持不变）；只有确认要发布一个全新的网页时才继续新建项目。"
                )
            }
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
        let project: LocalInteractiveWebProject?
        if let local = try await store.project(id: id) {
            project = local
        } else {
            project = try await store.project(remoteProjectID: id)
        }
        guard let project else {
            throw AgentToolError.invalidArguments("interactive webpage project not found for projectID '\(id)'. If this is an online project ID returned by interactive_web_list_projects or interactive_web_get_project and no local draft exists on this device, first download it with interactive_web_download_project(remoteProjectID: \"\(id)\"), then retry with the returned local projectID.")
        }
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
            fileNames: manifest.files.map(\.path),
            remoteProjectID: project.remoteProjectID,
            remoteSiteID: project.remoteSiteID,
            latestDeploymentID: project.latestDeploymentID,
            publishedURL: project.publishedURL,
            incompleteWrites: project.incompleteWrites ?? []
        )
    }

    private func write(_ content: String, named name: String, in root: URL) throws {
        try validate(content, named: name)
        let data = Data(content.utf8)
        let target = root.appendingPathComponent(name).standardizedFileURL
        guard target.deletingLastPathComponent() == root.standardizedFileURL else { throw AgentToolError.invalidArguments("invalid draft path") }
        try data.write(to: target, options: .atomic)
    }

    private func saveFile(named name: String, content: String, in root: URL) throws -> [InteractiveWebDraftFileChange] {
        let target = root.appendingPathComponent(name).standardizedFileURL
        let exists = fileManager.fileExists(atPath: target.path)
        let before = exists ? (try? String(contentsOf: target, encoding: .utf8)) ?? "" : ""
        try write(content, named: name, in: root)
        return [InteractiveWebDraftFileChange(
            fileName: name,
            operation: exists ? "updated" : "created",
            beforeHash: exists ? Self.sha256(before) : "",
            afterHash: Self.sha256(content),
            beforeSizeBytes: exists ? before.utf8.count : 0,
            afterSizeBytes: content.utf8.count,
            diff: exists ? Self.unifiedDiff(before: before, after: content, filePath: name) : ""
        )]
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
        guard Data(content.utf8).count <= 20 * 1_024 * 1_024 else {
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

    /// index.html 是否已链接 style.css（大小写不敏感，兼容单双引号与 ./style.css）。
    private func hasStylesheetLink(_ html: String) -> Bool {
        let lower = html.lowercased()
        var cursor = lower.startIndex
        while let open = lower.range(of: "<link", range: cursor..<lower.endIndex) {
            guard let close = lower.range(of: ">", range: open.upperBound..<lower.endIndex) else { return false }
            let tag = lower[open.lowerBound..<close.upperBound]
            if (tag.contains("rel=\"stylesheet\"") || tag.contains("rel='stylesheet'")), tag.contains("style.css") {
                return true
            }
            cursor = close.upperBound
        }
        return false
    }

    /// 在 <head> 开头（或 </head> 前）注入 style.css 链接；无 head 时放在文档最前面。
    private func injectStylesheetLink(_ html: String) -> String {
        let link = "<link rel=\"stylesheet\" href=\"style.css\">"
        let lower = html.lowercased()
        if let headOpen = lower.range(of: "<head") {
            if let headEnd = lower.range(of: ">", range: headOpen.upperBound..<lower.endIndex) {
                let insertAt = headEnd.upperBound
                return String(html[..<insertAt]) + "\n    " + link + String(html[insertAt...])
            }
        }
        if let headClose = lower.range(of: "</head>") {
            return String(html[..<headClose.lowerBound]) + "    " + link + "\n" + String(html[headClose.lowerBound...])
        }
        return link + "\n" + html
    }

    /// 若 style.css 存在而 index.html 未链接它，自动注入 <link> 并返回变更记录（供结果向模型报告）。
    private func ensureCssLinked(in root: URL) throws -> InteractiveWebDraftFileChange? {
        let indexURL = root.appendingPathComponent("index.html")
        let cssURL = root.appendingPathComponent("style.css")
        guard fileManager.fileExists(atPath: indexURL.path), fileManager.fileExists(atPath: cssURL.path) else { return nil }
        let before = try String(contentsOf: indexURL, encoding: .utf8)
        guard !hasStylesheetLink(before) else { return nil }
        let after = injectStylesheetLink(before)
        try Data(after.utf8).write(to: indexURL, options: .atomic)
        return InteractiveWebDraftFileChange(
            fileName: "index.html",
            operation: "css-link-injected",
            beforeHash: Self.sha256(before),
            afterHash: Self.sha256(after),
            beforeSizeBytes: before.utf8.count,
            afterSizeBytes: after.utf8.count,
            diff: Self.unifiedDiff(before: before, after: after, filePath: "index.html")
        )
    }

    private func containsInlineScript(_ html: String) -> Bool {
        let lower = html.lowercased()
        var cursor = lower.startIndex
        while let open = lower.range(of: "<script", range: cursor..<lower.endIndex) {
            // 跳过 HTML 注释中的 "<script" 字样（例如「<!-- 原内联 <script> 已移除 -->」）。
            // 注释不是可执行脚本，不应触发内联脚本拒绝，否则合法编辑会被误报失败。
            if let commentStart = lower.range(of: "<!--", range: cursor..<lower.endIndex),
               commentStart.lowerBound < open.lowerBound,
               let commentEnd = lower.range(of: "-->", range: open.lowerBound..<lower.endIndex) {
                cursor = commentEnd.upperBound
                continue
            }
            guard let close = lower.range(of: ">", range: open.upperBound..<lower.endIndex) else { break }
            let tag = lower[open.lowerBound..<close.upperBound]
            if !tag.contains("src=") { return true }
            cursor = close.upperBound
        }
        return false
    }

    private static func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 单文件统一 diff：只输出首尾公共行之外的变更段，便于任何模型用文本核对。
    private static func unifiedDiff(before: String, after: String, filePath: String, maxLines: Int = 400) -> String {
        let beforeLines = before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let afterLines = after.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard beforeLines != afterLines else { return "" }

        var prefix = 0
        let commonCount = min(beforeLines.count, afterLines.count)
        while prefix < commonCount, beforeLines[prefix] == afterLines[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < commonCount - prefix,
              beforeLines[beforeLines.count - 1 - suffix] == afterLines[afterLines.count - 1 - suffix] {
            suffix += 1
        }
        let removed = beforeLines[prefix..<(beforeLines.count - suffix)]
        let added = afterLines[prefix..<(afterLines.count - suffix)]

        var lines: [String] = [
            "--- a/\(filePath)",
            "+++ b/\(filePath)",
            "@@ -\(prefix + 1),\(removed.count) +\(prefix + 1),\(added.count) @@"
        ]
        var emitted = 0
        var truncated = false
        for line in removed {
            if emitted >= maxLines { truncated = true; break }
            lines.append("-\(line)")
            emitted += 1
        }
        for line in added {
            if emitted >= maxLines { truncated = true; break }
            lines.append("+\(line)")
            emitted += 1
        }
        if truncated { lines.append("... (diff truncated; use get_draft to read the full file)") }
        return lines.joined(separator: "\n")
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
        case editDraft = "interactive_web_edit_draft"
        case getDraft = "interactive_web_get_draft"
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
		case .createDraft, .editDraft, .downloadProject: .createInteractiveWebDraft
		case .getDraft, .getStatus: .readSession
		case .listProjects, .getProject, .recordsSummary: .externalNetwork
        case .publish, .rollback, .setAccess, .offline, .exportRecords: .publishInteractiveWeb
        }
    }
    public var description: String {
        switch operation {
		case .sdkUsage: "Request the interactive-web guide: the complete SDK v1 specification — backend-provided script path (/api/v1/sdk/v1.js), window.platform API surface, form and event conventions, submission feedback and already-submitted states, login gating rules, data-access rules, aggregate statistics scope, and a minimal example. You MUST call this before using any interactive-web functionality; generate or edit webpage drafts strictly per the returned specification and never reconstruct page interactions from memory."
		case .listProjects: "List the signed-in user's published interactive webpage projects, one page at a time (default 50 per page, max 100). Each project includes its publishedURL. Continue with page until fewer than limit items are returned. When the user asks to MODIFY an existing webpage (for example by pasting its link or naming it), you MUST first list projects and match the exact publishedURL or name; then download that project with interactive_web_download_project(remoteProjectID=its id), edit the downloaded draft with interactive_web_create_draft(projectID=...) or interactive_web_edit_draft, and publish the SAME projectID — the URL and collected data stay with the project. NEVER create a new project to revise an existing webpage: a new project gets a new URL while the old link keeps serving the old content."
		case .getProject: "Read an owned online webpage project's details, deployments, file manifest, and data collection names."
		case .downloadProject: "Download an owned online webpage's current files into Connor's user data directory and register an editable local draft."
        case .createDraft: "Create a new local interactive webpage draft, or update an existing one. Two write modes: (1) Complete mode — omit projectID and pass the complete name/html/css/javascript/collections (or update with the SAME projectID and full edited files; files you do not pass, such as css, stay unchanged). (2) Chunked mode from the very start — pass fileName (default index.html), content (the current chunk), offset (default 0) and final (default false); chunks are concatenated locally in order, continue with offset=nextOffset from each result, and set final=true on the last chunk so the file is validated and marked complete. A draft is NOT created successfully until every chunked file has final=true: get_status shows incompleteWrites and publish rejects incomplete drafts; never compress or cut page content to fit a shorter output. Before any interactive-web use (creating or updating), call interactive_web_sdk_usage in this session to get the complete SDK contract and example; updates often happen in a separate session, so never skip the guide. Every page must load the backend-provided absolute SDK path /api/v1/sdk/v1.js and use window.platform instead of constructing API URLs; put all page JavaScript in the javascript parameter (app.js) and never write inline <script> blocks (CSP blocks them); drafts without the SDK script or with inline scripts are rejected with step-by-step fix guidance. If you pass CSS (saved as style.css), index.html must link it with a stylesheet link; the runtime auto-injects a missing link and reports a css-link-injected change. Keep form controls (input/select/textarea/button) at consistent heights with matching font-size. The tool writes files into the app-managed user-data sandbox and does not publish anything."
        case .editDraft: "Edit one source file of an app-managed interactive webpage draft. Two modes (choose one): targeted edit — pass the exact oldText (must occur exactly once in the current file; read it first with interactive_web_get_draft) and newText (empty string deletes the oldText); or full-file replacement — pass content with the complete new file. For very large files, write content in chunks: start with offset=0 and content=first chunk, continue with offset=nextOffset from each result, and set final=true on the last chunk (the tool then truncates the old tail and validates the complete file). The tool applies each change atomically and returns the new revision, manifestHash, file hashes, the applied offset/nextOffset, and a plain-text unified diff. Edits to index.html must keep the SDK script tag (/api/v1/sdk/v1.js)."
        case .getDraft: "Read one source file from an app-managed interactive webpage draft; the result includes availableFiles so you can see which files exist in the draft. Use this before revising an existing draft so edits are based on the exact current source and manifest hash. Large files are paginated by character offset: the result reports totalCharacters and, when truncated, nextOffset — continue with offset=nextOffset to read the rest."
        case .getStatus: "Read the current local and published status of an interactive webpage project, including the list of draft files."
        case .publish: "Publish the exact current webpage revision to the internet and return its URL. Always requires native human approval; copy manifestHash exactly from interactive_web_create_draft (create or update) or interactive_web_get_status output. Publishing rejects drafts whose index.html omits the SDK script tag. Publishing a draft that came from interactive_web_download_project or was previously published keeps the SAME URL (the project's site is reused); only a brand-new draft (no remote project yet) gets a new URL. To revise an already-published webpage, download the original project and publish the same projectID — never create a new draft for that purpose."
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
                "projectID": .string(description: "Optional existing projectID to UPDATE instead of creating a new draft. Omit to create a new project."),
                "name": .string(description: "Webpage name; required when creating a new draft, optional when updating with projectID (the existing name is kept)"),
                "html": .string(description: "Complete index.html (edited for updates); omit when writing in chunks via content/fileName/offset/final"),
                "css": .string(description: "Optional stylesheet"),
                "javascript": .string(description: "Optional script"),
                "fileName": .string(description: "Optional target file for chunked creation; defaults to index.html. Allowed extensions: html, css, js, json, svg"),
                "content": .string(description: "Optional current chunk content. When provided, creates/continues ONE file in chunks (with fileName/offset/final); chunks are concatenated locally and the file is not complete until final=true. Omit to use the complete html/css/javascript mode."),
                "offset": .integer(description: "Optional 0-based character position for chunked creation; default 0. Continue with offset=nextOffset from the previous result."),
                "final": .boolean(description: "Optional; set true on the last chunk so the file is validated and marked complete. A draft is not created successfully until every chunked file has final=true."),
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
            ], required: [])
        case .editDraft:
            .closedObject(properties: [
                "projectID": .string(description: Self.localProjectIDDescription),
                "fileName": .string(description: "Relative text source path; see availableFiles in a get_draft or get_status result"),
                "content": .string(description: "Optional complete replacement content for the whole file (use instead of oldText/newText)"),
                "offset": .integer(description: "Optional 0-based character position where content should be written. Used to write large files in chunks; default 0. Continue with offset=nextOffset from the previous result."),
                "final": .boolean(description: "Optional; set true on the last content chunk so the tool truncates the old tail and validates the complete file."),
                "oldText": .string(description: "Optional exact text to replace; must occur exactly once in the current file. Use together with newText."),
                "newText": .string(description: "Optional replacement text; empty string deletes the oldText.")
            ], required: ["projectID", "fileName"])
        case .getDraft:
			.closedObject(properties: [
				"projectID": .string(description: Self.localProjectIDDescription),
				"fileName": .string(description: "Relative text source path; see availableFiles in a get_draft or get_status result"),
				"offset": .integer(description: "Optional 0-based character offset to start reading from. Defaults to 0; when the result is truncated, continue with offset=nextOffset."),
				"limit": .integer(description: "Optional maximum number of characters to return. Defaults to 100000; maximum 1000000.")
			], required: ["projectID", "fileName"])
        case .getStatus, .offline:
            .closedObject(properties: ["projectID": .string(description: Self.localProjectIDDescription)], required: ["projectID"])
        case .publish:
            .object(properties: ["projectID": .string(description: Self.localProjectIDDescription), "manifestHash": .string(description: "Exact 64-character hash from the latest local status"), "accessMode": .stringEnumeration(values: ["public", "password", "private"], description: "Who can access the site"), "password": .string(description: "Required only for password access")], required: ["projectID", "manifestHash", "accessMode"])
        case .rollback:
            .closedObject(properties: ["projectID": .string(description: Self.localProjectIDDescription), "deploymentID": .string(description: "Target deployment ID")], required: ["projectID", "deploymentID"])
        case .setAccess:
            .object(properties: ["projectID": .string(description: Self.localProjectIDDescription), "accessMode": .stringEnumeration(values: ["public", "password", "private"], description: "Who can access the site"), "password": .string(description: "Required only for password access")], required: ["projectID", "accessMode"])
        case .recordsSummary:
            .object(properties: ["projectID": .string(description: "Exact local project ID, or the online project ID from interactive_web_list_projects"), "collection": .string(description: "Collection name"), "limit": .integer(description: "1 through 1000"), "page": .integer(description: "1-based page number; default 1")], required: ["projectID", "collection"])
        case .exportRecords:
            .closedObject(properties: ["projectID": .string(description: "Exact local project ID, or the online project ID from interactive_web_list_projects"), "collection": .string(description: "Collection name")], required: ["projectID", "collection"])
        }
    }

    public init(operation: Operation, runtime: InteractiveWebToolRuntime) { self.operation = operation; self.runtime = runtime }

    private static let localProjectIDDescription = "Exact local draft project ID from interactive_web_create_draft, interactive_web_download_project, or interactive_web_get_status. An online project ID returned by interactive_web_list_projects or interactive_web_get_project resolves to the matching current local draft when it exists on this device; otherwise download it first with interactive_web_download_project."

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
            let chunked = arguments.string("content") != nil
            let save = try await runtime.createDraft(
                sessionID: context.sessionID,
                name: arguments.string("name") ?? "",
                html: arguments.string("html") ?? "",
                css: optionalString("css", arguments),
                javascript: optionalString("javascript", arguments),
                collections: try parseCollections(arguments),
                projectID: arguments.string("projectID"),
                fileName: arguments.string("fileName"),
                content: arguments.string("content"),
                offset: arguments.int("offset") ?? 0,
                final: arguments.bool("final") ?? false
            )
            status = save.status
            json = try encode(save)
            let changeLines = save.changes.map { change in
                "\(change.fileName): \(change.operation) (\(change.beforeSizeBytes) -> \(change.afterSizeBytes) bytes)\n\(change.diff)"
            }.joined(separator: "\n")
            if chunked, let nextOffset = save.nextOffset {
                text = "Chunk written (file not complete yet): continue with offset=\(nextOffset) on the same projectID until final=true.\n" + changeLines
            } else if chunked {
                text = "Chunk final written; file is now complete and validated.\n" + changeLines
            } else {
                text = "Local webpage draft \(arguments.string("projectID") == nil ? "created" : "updated").\n" + changeLines
            }
        case .editDraft:
            let rawOldText = arguments.string("oldText")
            let rawNewText = arguments.string("newText") ?? ""
            guard arguments.string("content") != nil || rawOldText != nil else {
                throw AgentToolError.invalidArguments("edit requires either oldText+newText (targeted edit) or content (full-file replacement)")
            }
            let edit = try await runtime.editDraft(
                projectID: requiredString("projectID", arguments),
                fileName: requiredString("fileName", arguments),
                oldText: rawOldText,
                newText: rawNewText,
                content: arguments.string("content"),
                offset: arguments.int("offset") ?? 0,
                final: arguments.bool("final") ?? false
            )
            status = edit.status
            json = try encode(edit)
            text = "Local webpage draft edited: \(edit.fileName) (\(edit.beforeSizeBytes) -> \(edit.afterSizeBytes) bytes).\n\(edit.diff)"
        case .getDraft:
            status = nil
            let source = try await runtime.draftSource(
                projectID: requiredString("projectID", arguments),
                fileName: requiredString("fileName", arguments),
                offset: arguments.int("offset") ?? 0,
                limit: arguments.int("limit")
            )
            json = try encode(source)
            let windowEnd = source.offset + source.content.count
            let remainingNote = source.truncated ? "; remaining \(source.remainingCharacters) chars (~\(source.estimatedRemainingCalls) calls)" : ""
            let continuation = source.truncated ? "; continue with offset=\(source.nextOffset ?? windowEnd)" : ""
            text = "Loaded \(source.fileName) from draft projectID=\(source.projectID), revision=\(source.revision), manifestHash=\(source.manifestHash) (characters \(source.offset)-\(windowEnd) of \(source.totalCharacters)\(remainingNote)\(continuation))."
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
        if let status, json == nil { json = try encode(status) }
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
