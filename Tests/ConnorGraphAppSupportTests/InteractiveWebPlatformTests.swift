import Foundation
import Testing
import ConnorGraphAgent
@testable import ConnorGraphAppSupport

struct InteractiveWebPlatformTests {
    @Test func validatesChoiceBatch() throws {
        let request = InteractiveWebChoiceRequest(choiceRequestID: "cr", accountID: "account", conversationID: "conversation", contextRevision: 1, selectors: [
            .init(id: "access", prompt: "访问方式", mode: .single, options: [.init(id: "public", label: "公开")])
        ])
        try InteractiveWebChoiceValidator.validate(.init(choiceRequestID: "cr", selections: [.init(selectorID: "access", optionIDs: ["public"])]), for: request)
        #expect(throws: InteractiveWebChoiceError.self) { try InteractiveWebChoiceValidator.validate(.init(choiceRequestID: "cr", selections: []), for: request) }
    }

    @Test func packagesStaticFilesDeterministically() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        try Data("<h1>Hello</h1>".utf8).write(to: root.appendingPathComponent("index.html")); try Data("body{}".utf8).write(to: root.appendingPathComponent("style.css"))
        let manifest = try InteractiveWebPackager().package(rootURL: root)
        #expect(manifest.files.map(\.path) == ["index.html", "style.css"])
    }

    @Test func manifestCarriesRegistrationSchema() {
        let manifest = InteractiveWebManifest(files: [], collections: [
            .init(name: "registrations", fields: [.init(name: "name", type: "string", required: true, maxLength: 80)], anonymousCreate: true)
        ])
        #expect(manifest.collections.first?.name == "registrations")
    }

    @Test func packageReadsCollectionSchemaFromProjectConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("<form></form>".utf8).write(to: root.appendingPathComponent("index.html"))
        let collection = InteractiveWebCollectionDefinition(
            name: "registrations",
            fields: [.init(name: "student_name", type: "string", required: true, maxLength: 80, pattern: "^.+$")],
            anonymousCreate: true
        )
        try Data(InteractiveWebPackager.configurationJSON(collections: [collection]).utf8)
            .write(to: root.appendingPathComponent(InteractiveWebPackager.configurationFileName))

        let manifest = try InteractiveWebPackager().package(rootURL: root)
        #expect(manifest.collections == [collection])
        #expect(manifest.collections.first?.fields.first?.pattern == "^.+$")
        #expect(manifest.files.map(\.path) == ["connor.web.json", "index.html"])
    }

    @Test func packageConvertsUnicodeEscapesToBackendCompatibleForm() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("<form></form>".utf8).write(to: root.appendingPathComponent("index.html"))
        let icuPattern = #"^[A-Za-z0-9@._+\-\s\u4e00-\u9fa5]{2,60}$"#
        let collection = InteractiveWebCollectionDefinition(
            name: "messages",
            fields: [.init(name: "contact", type: "string", maxLength: 60, pattern: icuPattern)],
            anonymousCreate: true,
            readStats: "public"
        )
        try Data(InteractiveWebPackager.configurationJSON(collections: [collection]).utf8)
            .write(to: root.appendingPathComponent(InteractiveWebPackager.configurationFileName))

        let packager = InteractiveWebPackager()
        let manifest = try packager.package(rootURL: root)
        let normalized = try #require(manifest.collections.first?.fields.first?.pattern)
        #expect(normalized == #"^[A-Za-z0-9@._+\-\s\x{4e00}-\x{9fa5}]{2,60}$"#)
        #expect(normalized.contains(#"\u"#) == false)

        // The manifest hash must be computed over the normalized manifest, so the hash
        // reported by get_status matches what publish sends to the backend.
        let expectedManifest = InteractiveWebManifest(files: manifest.files, collections: [
            InteractiveWebCollectionDefinition(
                name: "messages",
                fields: [.init(name: "contact", type: "string", maxLength: 60, pattern: normalized)],
                anonymousCreate: true,
                readStats: "public"
            )
        ])
        #expect(packager.fingerprint(manifest) == packager.fingerprint(expectedManifest))
    }

    @Test func packageRejectsPatternsUnsupportedByBackendRegexEngine() throws {
        let unsupportedPatterns: [(name: String, pattern: String)] = [
            ("lookahead", #"^(?=.*\d).{8,20}$"#),
            ("lookbehind", #"^(?<=\d)abc$"#),
            ("backreference", #"^(ab)\1$"#),
            ("named backreference", #"^(?<x>ab)\k<x>$"#),
            ("atomic group", #"^(?>ab)$"#),
            ("possessive quantifier", #"^a*+$"#),
            ("conditional", #"^(?(1)ab|cd)$"#),
        ]
        for item in unsupportedPatterns {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("interactive-web-re2-\(item.name)-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try Data("<form></form>".utf8).write(to: root.appendingPathComponent("index.html"))
            let collection = InteractiveWebCollectionDefinition(
                name: "messages",
                fields: [.init(name: "contact", type: "string", maxLength: 60, pattern: item.pattern)],
                anonymousCreate: true
            )
            try Data(InteractiveWebPackager.configurationJSON(collections: [collection]).utf8)
                .write(to: root.appendingPathComponent(InteractiveWebPackager.configurationFileName))
            do {
                _ = try InteractiveWebPackager().package(rootURL: root)
                Issue.record("Expected \(item.name) pattern to be rejected")
            } catch let error as InteractiveWebConfigurationError {
                #expect(error.message.contains("RE2"))
            }
        }
    }

    @Test func packageAcceptsLiteralMetaCharactersInsideCharacterClasses() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("interactive-web-re2-class-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("<form></form>".utf8).write(to: root.appendingPathComponent("index.html"))
        // Parentheses, lookaround punctuation, possessive-looking characters and a
        // unicode escape all live inside a character class here and must not be flagged.
        let pattern = #"^[()?=!*+\u4e00-\u9fa5]+$"#
        let collection = InteractiveWebCollectionDefinition(
            name: "messages",
            fields: [.init(name: "contact", type: "string", maxLength: 60, pattern: pattern)],
            anonymousCreate: true
        )
        try Data(InteractiveWebPackager.configurationJSON(collections: [collection]).utf8)
            .write(to: root.appendingPathComponent(InteractiveWebPackager.configurationFileName))
        let manifest = try InteractiveWebPackager().package(rootURL: root)
        #expect(manifest.collections.first?.fields.first?.pattern == #"^[()?=!*+\x{4e00}-\x{9fa5}]+$"#)
    }

    @Test func packageCarriesSubmitLimitRulesAndFingerprint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("<form></form>".utf8).write(to: root.appendingPathComponent("index.html"))
        let loginOnly = InteractiveWebCollectionDefinition(
            name: "registrations",
            fields: [.init(name: "name", type: "string", required: true, maxLength: 80)],
            anonymousCreate: false,
            anonymousRead: false,
            submitLimit: .init(max: 1, window: "lifetime", scope: "account")
        )
        try Data(InteractiveWebPackager.configurationJSON(collections: [loginOnly]).utf8)
            .write(to: root.appendingPathComponent(InteractiveWebPackager.configurationFileName))

        let manifest = try InteractiveWebPackager().package(rootURL: root)
        #expect(manifest.collections.first?.submitLimit == .init(max: 1, window: "lifetime", scope: "account"))
        let withoutLimit = InteractiveWebManifest(files: manifest.files, collections: [
            .init(name: "registrations", fields: loginOnly.fields, anonymousCreate: false, anonymousRead: false)
        ])
        #expect(InteractiveWebPackager().fingerprint(manifest) != InteractiveWebPackager().fingerprint(withoutLimit))

        let invalidRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: invalidRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: invalidRoot) }
        try Data("<form></form>".utf8).write(to: invalidRoot.appendingPathComponent("index.html"))
        let invalid = InteractiveWebCollectionDefinition(
            name: "checkins",
            fields: [.init(name: "note", type: "string", maxLength: 80)],
            anonymousCreate: true,
            anonymousRead: false,
            submitLimit: .init(max: 1, window: "lifetime", scope: "account")
        )
        try Data(InteractiveWebPackager.configurationJSON(collections: [invalid]).utf8)
            .write(to: invalidRoot.appendingPathComponent(InteractiveWebPackager.configurationFileName))
        #expect(throws: InteractiveWebConfigurationError.self) {
            _ = try InteractiveWebPackager().package(rootURL: invalidRoot)
        }
    }

    @Test func packageAcceptsSubmitLimitAndReadStatsConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("<form></form>".utf8).write(to: root.appendingPathComponent("index.html"))
        let configured = InteractiveWebCollectionDefinition(
            name: "registrations",
            fields: [
                .init(name: "name", type: "string", required: true, maxLength: 40),
                .init(name: "guests", type: "number", required: false, maxLength: 0),
                .init(name: "message", type: "string", required: false, maxLength: 500),
            ],
            anonymousCreate: false,
            anonymousRead: false,
            submitLimit: .init(max: 1, window: "lifetime", scope: "account"),
            readStats: "owner"
        )
        try Data(InteractiveWebPackager.configurationJSON(collections: [configured]).utf8)
            .write(to: root.appendingPathComponent(InteractiveWebPackager.configurationFileName))

        let manifest = try InteractiveWebPackager().package(rootURL: root)
        #expect(manifest.collections.first?.readStats == "owner")
        #expect(manifest.collections.first?.submitLimit == .init(max: 1, window: "lifetime", scope: "account"))
    }

    @Test func packageReportsInvalidReadStatsWithActionableMessage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("<form></form>".utf8).write(to: root.appendingPathComponent("index.html"))
        let invalid = InteractiveWebCollectionDefinition(
            name: "registrations",
            fields: [.init(name: "name", type: "string", required: true, maxLength: 40)],
            anonymousCreate: false,
            anonymousRead: false,
            readStats: "private"
        )
        try Data(InteractiveWebPackager.configurationJSON(collections: [invalid]).utf8)
            .write(to: root.appendingPathComponent(InteractiveWebPackager.configurationFileName))

        do {
            _ = try InteractiveWebPackager().package(rootURL: root)
            Issue.record("expected invalid readStats to be rejected")
        } catch let error as InteractiveWebConfigurationError {
            #expect(error.message.contains("readStats"))
            #expect(error.message.contains("owner"))
        } catch {
            Issue.record("expected InteractiveWebConfigurationError, got \(error)")
        }
    }

    @Test func accessModesRemainProtocolStable() {
        #expect([
            InteractiveWebAccessMode.public.rawValue,
            InteractiveWebAccessMode.password.rawValue,
            InteractiveWebAccessMode.private.rawValue
        ] == ["public", "password", "private"])
    }

	@Test func submittedRecordPreservesUserData() throws {
		let payload = Data(#"{"id":"record-1","data":{"name":"Lin","attending":true,"guests":2},"status":"approved","createdAt":"2026-08-03T00:00:00Z"}"#.utf8)
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let record = try decoder.decode(InteractiveWebRecordMetadata.self, from: payload)
		#expect(record.data["name"] == .string("Lin"))
		#expect(record.data["attending"] == .bool(true))
		#expect(record.data["guests"] == .number(2))
	}

    @Test func publishRejectsDraftChangedAfterApprovalBeforeNetworkAccess() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let approved = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: "<h1>Approved</h1><script src=\"../sdk/v1.js\"></script>",
            css: nil,
            javascript: nil
        )
        try Data("<h1>Changed</h1>".utf8).write(
            to: approved.status.rootURL.appendingPathComponent("index.html"),
            options: .atomic
        )

        await #expect(throws: AgentToolError.self) {
            _ = try await runtime.publish(
                projectID: approved.status.projectID,
                expectedManifestHash: approved.status.manifestHash,
                accessMode: .private,
                password: nil
            )
        }
    }

    @Test func publishingToolApprovalPayloadBindsRevisionHashAndSize() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let status = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: "<h1>Hello</h1><script src=\"../sdk/v1.js\"></script>",
            css: nil,
            javascript: nil
        )
        let tool = InteractiveWebAgentTool(operation: .publish, runtime: runtime)
        let call = AgentToolCall(
            name: tool.name,
            argumentsJSON: "{\"projectID\":\"\(status.status.projectID)\",\"manifestHash\":\"\(status.status.manifestHash)\",\"accessMode\":\"private\"}"
        )
        let context = AgentToolExecutionContext(
            runID: "run-1",
            sessionID: "session-1",
            groupID: "account",
            userPrompt: "publish",
            toolCallID: "call-1",
            policyEngine: AgentPolicyEngine(permissionMode: .askToWrite)
        )

        let payload = await tool.approvalPayloadJSON(for: call, context: context)
        let object = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        #expect(object["revision"] as? Int == status.status.revision)
        #expect(object["manifestHash"] as? String == status.status.manifestHash)
        #expect(object["fileCount"] as? Int == status.status.fileCount)
        #expect((object["totalBytes"] as? NSNumber)?.int64Value == status.status.totalBytes)
        #expect(object["accessMode"] as? String == "private")
    }

    @Test func publishPreflightAcceptsCurrentManifestAndRejectsStaleManifest() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let status = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: "<main><h1>Ready</h1></main><script src=\"../sdk/v1.js\"></script>",
            css: nil,
            javascript: nil
        )
        let tool = InteractiveWebAgentTool(operation: .publish, runtime: runtime)
        let call = AgentToolCall(
            name: tool.name,
            argumentsJSON: "{\"projectID\":\"\(status.status.projectID)\",\"manifestHash\":\"\(status.status.manifestHash)\",\"accessMode\":\"private\"}"
        )
        let context = AgentToolExecutionContext(
            runID: "run-1",
            sessionID: "session-1",
            groupID: "account",
            userPrompt: "publish",
            toolCallID: "call-1",
            policyEngine: AgentPolicyEngine(permissionMode: .askToWrite)
        )

        try await tool.preflight(call: call, context: context)

        try Data("<main><h1>Changed</h1></main><script src=\"../sdk/v1.js\"></script>".utf8).write(
            to: status.status.rootURL.appendingPathComponent("index.html"),
            options: .atomic
        )
        await #expect(throws: AgentToolError.self) {
            try await tool.preflight(call: call, context: context)
        }
    }

    @Test func createDraftRejectsHtmlWithoutSDKWithGuidance() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        do {
            _ = try await runtime.createDraft(sessionID: "session-1", name: "Result", html: "<h1>No SDK</h1>", css: nil, javascript: nil)
            Issue.record("createDraft must reject index.html without the SDK")
        } catch let error as AgentToolError {
            let message = String(describing: error)
            #expect(message.contains("/api/v1/sdk/v1.js"))
            #expect(message.contains("Fix it step by step"))
            #expect(message.contains("window.platform.auth.login"))
        }
    }

    @Test func publishPreflightRejectsDraftWithoutSDKWithGuidance() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let created = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: "<h1>Ready</h1><script src=\"../sdk/v1.js\"></script>",
            css: nil,
            javascript: nil
        )
        try Data("<h1>No SDK</h1>".utf8).write(to: created.status.rootURL.appendingPathComponent("index.html"), options: .atomic)
        let current = try await runtime.status(projectID: created.status.projectID)
        let tool = InteractiveWebAgentTool(operation: .publish, runtime: runtime)
        let call = AgentToolCall(
            name: tool.name,
            argumentsJSON: "{\"projectID\":\"\(created.status.projectID)\",\"manifestHash\":\"\(current.manifestHash)\",\"accessMode\":\"private\"}"
        )
        let context = AgentToolExecutionContext(
            runID: "run-1",
            sessionID: "session-1",
            groupID: "account",
            userPrompt: "publish",
            toolCallID: "call-1",
            policyEngine: AgentPolicyEngine(permissionMode: .askToWrite)
        )
        do {
            try await tool.preflight(call: call, context: context)
            Issue.record("publish preflight must reject index.html without the SDK")
        } catch let error as AgentToolError {
            #expect(String(describing: error).contains("Fix it step by step"))
        }
    }

    @Test func sdkUsageToolReturnsCompleteContract() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let tool = InteractiveWebAgentTool(operation: .sdkUsage, runtime: runtime)
        let context = AgentToolExecutionContext(
            runID: "run-1",
            sessionID: "session-1",
            groupID: "account",
            userPrompt: "sdk usage",
            toolCallID: "call-1",
            policyEngine: AgentPolicyEngine(permissionMode: .askToWrite)
        )
        let result = try await tool.execute(
            arguments: try AgentToolArguments(json: "{}"),
            context: context
        )
        for expected in ["/api/v1/sdk/v1.js", "window.platform", "auth.login", "myRecords", "data-connor-collection", "connor:submit-error", "collection.rules", "data-connor-auth-required", "app.js", "script-src 'self'", "readStats", "Aggregate statistics scope", "Submission feedback must be prominent and polished", "hide or remove the fillable form", "Interactive-web guide", "Create and update use ONE tool", "20 MB"] {
            #expect(result.contentText.contains(expected), "SDK contract is missing \(expected)")
        }
    }

    @Test func createDraftRejectsInlineScriptWithGuidance() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        do {
            _ = try await runtime.createDraft(
                sessionID: "session-1",
                name: "Result",
                html: "<h1>Hi</h1><script src=\"/api/v1/sdk/v1.js\"></script><script>window.x=1</script>",
                css: nil,
                javascript: nil
            )
            Issue.record("createDraft must reject inline <script> blocks")
        } catch let error as AgentToolError {
            let message = String(describing: error)
            #expect(message.contains("inline <script>"))
            #expect(message.contains("app.js"))
        }
    }

    @Test func createDraftAcceptsExternalScriptPage() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let status = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: "<html><head><script src=\"/api/v1/sdk/v1.js\"></script></head><body><form data-connor-collection=\"registrations\" data-connor-auth-required=\"registrations\"></form><script src=\"app.js\"></script></body></html>",
            css: nil,
            javascript: "window.platform.auth.onAuthChange(() => {});"
        )
        #expect(status.status.fileCount >= 1)
    }

    @Test func statusReportsDraftFileNames() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let created = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: "<h1>Hello</h1><script src=\"../sdk/v1.js\"></script>",
            css: "body {}",
            javascript: "console.log(1)"
        )
        let status = try await runtime.status(projectID: created.status.projectID)
        #expect(status.fileNames.contains("index.html"))
        #expect(status.fileNames.contains("style.css"))
        #expect(status.fileNames.contains("app.js"))
    }

    @Test func draftSourceMissingFileErrorListsAvailableFiles() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let created = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: "<h1>Hello</h1><script src=\"../sdk/v1.js\"></script>",
            css: nil,
            javascript: nil
        )
        do {
            _ = try await runtime.draftSource(projectID: created.status.projectID, fileName: "styles.css")
            Issue.record("draftSource must reject a missing file")
        } catch let error as AgentToolError {
            let message = String(describing: error)
            #expect(message.contains("styles.css does not exist"))
            #expect(message.contains("index.html"))
        }
    }

    @Test func draftSourceResultIncludesAvailableFiles() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let created = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: "<h1>Hello</h1><script src=\"../sdk/v1.js\"></script>",
            css: "body {}",
            javascript: nil
        )
        let source = try await runtime.draftSource(projectID: created.status.projectID, fileName: "index.html")
        #expect(source.availableFiles.contains("index.html"))
        #expect(source.availableFiles.contains("style.css"))
    }

    @Test func draftSourcePaginatesLargeFilesByCharacterOffset() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let html = "<head><script src=\"/api/v1/sdk/v1.js\"></script></head><body>"
            + String(repeating: "<p>content</p>\n", count: 10_000)
            + "</body>"
        let created = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: html,
            css: nil,
            javascript: nil
        )

        let first = try await runtime.draftSource(projectID: created.status.projectID, fileName: "index.html", limit: 100_000)
        #expect(first.offset == 0)
        #expect(first.content.count == 100_000)
        #expect(first.totalCharacters == html.count)
        #expect(first.truncated)
        #expect(first.nextOffset == 100_000)
        #expect(first.remainingCharacters == html.count - 100_000)
        #expect(first.estimatedRemainingCalls == Int((Double(html.count - 100_000) / 100_000.0).rounded(.up)))

        let second = try await runtime.draftSource(projectID: created.status.projectID, fileName: "index.html", offset: first.nextOffset ?? 0, limit: 100_000)
        #expect(second.offset == 100_000)
        #expect(second.content == String(html.dropFirst(100_000)))
        #expect(second.truncated == false)
        #expect(second.nextOffset == nil)
        #expect(second.remainingCharacters == 0)
        #expect(second.estimatedRemainingCalls == 0)

        let tail = try await runtime.draftSource(projectID: created.status.projectID, fileName: "index.html", offset: 200_000)
        #expect(tail.offset == html.count)
        #expect(tail.content.isEmpty)
        #expect(tail.truncated == false)
        #expect(tail.nextOffset == nil)
    }

    @Test func createDraftWithProjectIDUpdatesExistingDraft() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let html = "<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>old</p>\n</body>"
        let created = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: html,
            css: "body {}",
            javascript: "console.log('v1')"
        )
        let projectID = created.status.projectID
        let updatedHTML = "<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>new</p>\n</body>"

        let updated = try await runtime.createDraft(
            sessionID: "session-1",
            name: "",
            html: updatedHTML,
            css: nil,
            javascript: nil,
            projectID: projectID
        )

        #expect(updated.status.projectID == projectID)
        #expect(updated.status.name == "Result")
        #expect(updated.status.revision == 2)
        #expect(updated.status.manifestHash != created.status.manifestHash)
        #expect(updated.changes.count == 1)
        let change = updated.changes[0]
        #expect(change.fileName == "index.html")
        #expect(change.operation == "updated")
        #expect(change.diff.contains("-<p>old</p>"))
        #expect(change.diff.contains("+<p>new</p>"))

        let source = try await runtime.draftSource(projectID: projectID, fileName: "index.html")
        #expect(source.content.contains("<p>new</p>"))
        #expect(!source.content.contains("<p>old</p>"))
        #expect(source.revision == 2)
        // 未传入的 css/js 保持不变
        let css = try await runtime.draftSource(projectID: projectID, fileName: "style.css")
        #expect(css.content == "body {}")
        let js = try await runtime.draftSource(projectID: projectID, fileName: "app.js")
        #expect(js.content == "console.log('v1')")
    }

    @Test func createDraftWithoutProjectIDCreatesSeparateProject() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let html = "<head><script src=\"/api/v1/sdk/v1.js\"></script></head><body><p>x</p></body>"
        let first = try await runtime.createDraft(sessionID: "session-1", name: "Result", html: html, css: nil, javascript: nil)
        let second = try await runtime.createDraft(sessionID: "session-1", name: "Result", html: html, css: nil, javascript: nil)
        #expect(first.status.projectID != second.status.projectID)
        #expect(first.status.revision == 1)
        #expect(second.status.revision == 1)
    }

    @Test func createDraftRequiresNameWhenCreating() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let html = "<head><script src=\"/api/v1/sdk/v1.js\"></script></head><body><p>x</p></body>"
        await #expect(throws: AgentToolError.self) {
            _ = try await runtime.createDraft(sessionID: "session-1", name: "", html: html, css: nil, javascript: nil)
        }
    }

    @Test func createDraftAllowsFilesLargerThanTwoMB() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let html = "<head><script src=\"/api/v1/sdk/v1.js\"></script></head><body>"
            + String(repeating: "x", count: 3_000_000)
            + "</body>"
        let created = try await runtime.createDraft(sessionID: "session-1", name: "Result", html: html, css: nil, javascript: nil)
        #expect(created.status.totalBytes > 2 * 1_024 * 1_024)
        // 读取大文件也按 20MB 上限放行
        let source = try await runtime.draftSource(projectID: created.status.projectID, fileName: "index.html", limit: 100_000)
        #expect(source.totalCharacters > 3_000_000)
    }

    @Test func createDraftToolUpdateReturnsTextDiffAndNewHash() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let status = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: "<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>old</p>\n</body>",
            css: nil,
            javascript: nil
        )
        let tool = InteractiveWebAgentTool(operation: .createDraft, runtime: runtime)
        let context = AgentToolExecutionContext(
            runID: "run-1",
            sessionID: "session-1",
            groupID: "account",
            userPrompt: "update",
            toolCallID: "call-1",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
        let arguments = try AgentToolArguments(json: #"{"projectID":"\#(status.status.projectID)","name":"Result","html":"<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>new</p>\n</body>"}"#)

        let result = try await tool.execute(arguments: arguments, context: context)

        #expect(result.contentText.contains("updated"))
        #expect(result.contentText.contains("-<p>old</p>"))
        #expect(result.contentText.contains("+<p>new</p>"))
        #expect(result.contentText.contains("revision=2"))
        #expect(result.contentJSON?.contains("manifestHash") == true)
    }

    @Test func editDraftDeletesLineAndBumpsRevision() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let html = "<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>remove</p>\n<p>keep</p>\n</body>"
        let created = try await runtime.createDraft(sessionID: "session-1", name: "Result", html: html, css: nil, javascript: nil)

        let edit = try await runtime.editDraft(
            projectID: created.status.projectID,
            fileName: "index.html",
            oldText: "<p>remove</p>\n",
            newText: "",
            content: nil
        )

        #expect(edit.fileName == "index.html")
        #expect(edit.status.revision == 2)
        #expect(edit.status.manifestHash != created.status.manifestHash)
        #expect(edit.afterSizeBytes < edit.beforeSizeBytes)
        #expect(edit.diff.contains("-<p>remove</p>"))
        #expect(!edit.diff.contains("+<p>remove</p>"))

        let source = try await runtime.draftSource(projectID: created.status.projectID, fileName: "index.html")
        #expect(!source.content.contains("<p>remove</p>"))
        #expect(source.content.contains("<p>keep</p>"))
        #expect(source.revision == 2)
    }

    @Test func editDraftSupportsWholeFileReplacement() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let html = "<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>old</p>\n</body>"
        let created = try await runtime.createDraft(sessionID: "session-1", name: "Result", html: html, css: "body {}", javascript: nil)

        let replacement = "<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>brand new</p>\n</body>"
        let edit = try await runtime.editDraft(
            projectID: created.status.projectID,
            fileName: "index.html",
            oldText: nil,
            newText: nil,
            content: replacement
        )

        #expect(edit.status.revision == 2)
        #expect(edit.beforeHash != edit.afterHash)
        #expect(edit.diff.contains("-<p>old</p>"))
        #expect(edit.diff.contains("+<p>brand new</p>"))
        let source = try await runtime.draftSource(projectID: created.status.projectID, fileName: "index.html")
        #expect(source.content == replacement)
        // 未修改的文件保持不变
        let css = try await runtime.draftSource(projectID: created.status.projectID, fileName: "style.css")
        #expect(css.content == "body {}")
    }

    @Test func editDraftSupportsChunkedWholeFileReplacement() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let html = "<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>old</p>\n</body>"
        let created = try await runtime.createDraft(sessionID: "session-1", name: "Result", html: html, css: nil, javascript: nil)

        let target = "<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>hello chunk</p>\n</body>"
        // 切分点选在差异发生之后（old 的 <p>old 与 target 的 <p>he 在第 69 个字符处分叉）
        let splitIndex = 70
        let chunk1 = String(target.prefix(splitIndex))
        let chunk2 = String(target.dropFirst(splitIndex))

        let first = try await runtime.editDraft(
            projectID: created.status.projectID,
            fileName: "index.html",
            oldText: nil,
            newText: nil,
            content: chunk1,
            offset: 0,
            final: false
        )
        #expect(first.nextOffset == splitIndex)
        #expect(first.status.revision == 2)
        #expect(first.diff.contains("-<p>old</p>"))

        let last = try await runtime.editDraft(
            projectID: created.status.projectID,
            fileName: "index.html",
            oldText: nil,
            newText: nil,
            content: chunk2,
            offset: first.nextOffset ?? 0,
            final: true
        )
        #expect(last.status.revision == 3)
        #expect(last.resultTotalCharacters == target.count)
        #expect(last.diff.contains("+<p>hello chunk</p>"))

        let source = try await runtime.draftSource(projectID: created.status.projectID, fileName: "index.html")
        #expect(source.content == target)
    }

    @Test func editDraftRejectsAmbiguousOldText() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let html = "<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>x</p>\n<p>x</p>\n</body>"
        let created = try await runtime.createDraft(sessionID: "session-1", name: "Result", html: html, css: nil, javascript: nil)

        do {
            _ = try await runtime.editDraft(projectID: created.status.projectID, fileName: "index.html", oldText: "<p>x</p>", newText: "<p>y</p>", content: nil)
            Issue.record("editDraft must reject an ambiguous oldText")
        } catch let error as AgentToolError {
            #expect(String(describing: error).contains("occur exactly once"))
            #expect(String(describing: error).contains("found 2"))
        }
    }

    @Test func editDraftRejectsMissingOldText() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let html = "<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>keep</p>\n</body>"
        let created = try await runtime.createDraft(sessionID: "session-1", name: "Result", html: html, css: nil, javascript: nil)

        do {
            _ = try await runtime.editDraft(projectID: created.status.projectID, fileName: "index.html", oldText: "<p>missing</p>", newText: "", content: nil)
            Issue.record("editDraft must reject a missing oldText")
        } catch let error as AgentToolError {
            #expect(String(describing: error).contains("found 0"))
        }
    }

    @Test func editDraftRejectsDroppingSDKScript() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let html = "<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>keep</p>\n</body>"
        let created = try await runtime.createDraft(sessionID: "session-1", name: "Result", html: html, css: nil, javascript: nil)

        do {
            _ = try await runtime.editDraft(projectID: created.status.projectID, fileName: "index.html", oldText: "<script src=\"/api/v1/sdk/v1.js\"></script>", newText: "", content: nil)
            Issue.record("editDraft must reject dropping the SDK script")
        } catch let error as AgentToolError {
            #expect(String(describing: error).contains("sdk/v1.js"))
        }
    }

    @Test func editDraftToolSupportsBothModes() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let status = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: "<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>old</p>\n</body>",
            css: nil,
            javascript: nil
        )
        let tool = InteractiveWebAgentTool(operation: .editDraft, runtime: runtime)
        let context = AgentToolExecutionContext(
            runID: "run-1",
            sessionID: "session-1",
            groupID: "account",
            userPrompt: "edit",
            toolCallID: "call-1",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )

        // 精确替换模式
        let targeted = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"projectID":"\#(status.status.projectID)","fileName":"index.html","oldText":"<p>old</p>","newText":"<p>new</p>"}"#),
            context: context
        )
        #expect(targeted.contentText.contains("-<p>old</p>"))
        #expect(targeted.contentText.contains("+<p>new</p>"))
        #expect(targeted.contentText.contains("revision=2"))
        #expect(targeted.contentJSON?.contains("manifestHash") == true)

        // 整文件替换模式
        let whole = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"projectID":"\#(status.status.projectID)","fileName":"index.html","content":"<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>full</p>\n</body>"}"#),
            context: context
        )
        #expect(whole.contentText.contains("revision=3"))
        #expect(whole.contentText.contains("-<p>new</p>"))
        #expect(whole.contentText.contains("+<p>full</p>"))
    }

    @Test func publishIDResolvesToCurrentLocalDraft() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let created = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: "<head><script src=\"/api/v1/sdk/v1.js\"></script></head>\n<body>\n<p>draft</p>\n</body>",
            css: nil,
            javascript: nil
        )
        let localID = created.status.projectID
        let store = InteractiveWebLocalStore(storagePaths: fixture.paths)
        guard var project = try await store.project(id: localID) else {
            Issue.record("local project must exist")
            return
        }
        project.remoteProjectID = "online-project-123"
        try await store.save(project: project)

        // 发布/线上 ID 直接解析到当前本地草稿
        let source = try await runtime.draftSource(projectID: "online-project-123", fileName: "index.html")
        #expect(source.content.contains("<p>draft</p>"))
        let status = try await runtime.status(projectID: "online-project-123")
        #expect(status.projectID == localID)

        let edit = try await runtime.editDraft(projectID: "online-project-123", fileName: "index.html", oldText: "<p>draft</p>", newText: "<p>updated</p>", content: nil)
        #expect(edit.status.projectID == localID)
        #expect(edit.status.revision == 2)
    }

    @Test func unknownProjectErrorExplainsRemoteIDDownloadPath() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        do {
            _ = try await runtime.status(projectID: "ea5d4b82-a4fc-4a6d-aaab-1d3a5c8081ad")
            Issue.record("status must reject an unknown project")
        } catch let error as AgentToolError {
            let message = String(describing: error)
            #expect(message.contains("interactive_web_download_project"))
            #expect(message.contains("ea5d4b82-a4fc-4a6d-aaab-1d3a5c8081ad"))
        }
    }

    private func makeRuntimeFixture() throws -> (paths: AppStoragePaths, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConnorInteractiveWebRuntime-", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        return (paths, root)
    }
}
