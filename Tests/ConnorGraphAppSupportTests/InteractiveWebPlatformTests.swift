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
        #expect(throws: CocoaError.self) {
            _ = try InteractiveWebPackager().package(rootURL: invalidRoot)
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
            to: approved.rootURL.appendingPathComponent("index.html"),
            options: .atomic
        )

        await #expect(throws: AgentToolError.self) {
            _ = try await runtime.publish(
                projectID: approved.projectID,
                expectedManifestHash: approved.manifestHash,
                accessMode: .private,
                password: nil
            )
        }
    }

    @Test func draftSourceSupportsExactEditsAndRejectsStaleUpdates() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let created = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: "<h1>Hello</h1><script src=\"../sdk/v1.js\"></script>",
            css: "h1 { color: red; }",
            javascript: nil
        )

        let source = try await runtime.draftSource(projectID: created.projectID, fileName: "index.html")
        #expect(source.content == "<h1>Hello</h1><script src=\"../sdk/v1.js\"></script>")
        #expect(source.manifestHash == created.manifestHash)

        let updated = try await runtime.updateDraft(
            projectID: created.projectID,
            expectedManifestHash: source.manifestHash,
            replacements: [:],
            edits: ["index.html": [(oldText: "Hello", newText: "Finished")]]
        )
        #expect(updated.revision == 2)
        #expect(try String(contentsOf: created.rootURL.appendingPathComponent("index.html"), encoding: .utf8) == "<h1>Finished</h1><script src=\"../sdk/v1.js\"></script>")
        #expect(try String(contentsOf: created.rootURL.appendingPathComponent("style.css"), encoding: .utf8) == "h1 { color: red; }")

        await #expect(throws: AgentToolError.self) {
            _ = try await runtime.updateDraft(
                projectID: created.projectID,
                expectedManifestHash: source.manifestHash,
                replacements: ["style.css": "h1 { color: blue; }"],
                edits: [:]
            )
        }
    }

    @Test func invalidMultiFileEditLeavesDraftUnchanged() async throws {
        let fixture = try makeRuntimeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = InteractiveWebToolRuntime(storagePaths: fixture.paths, accountID: "account", api: nil)
        let created = try await runtime.createDraft(
            sessionID: "session-1",
            name: "Result",
            html: "<h1>Hello</h1><script src=\"../sdk/v1.js\"></script>",
            css: "h1 { color: red; }",
            javascript: nil
        )

        await #expect(throws: AgentToolError.self) {
            _ = try await runtime.updateDraft(
                projectID: created.projectID,
                expectedManifestHash: created.manifestHash,
                replacements: ["style.css": "h1 { color: blue; }"],
                edits: ["index.html": [(oldText: "Missing", newText: "Finished")]]
            )
        }
        #expect(try String(contentsOf: created.rootURL.appendingPathComponent("index.html"), encoding: .utf8) == "<h1>Hello</h1><script src=\"../sdk/v1.js\"></script>")
        #expect(try String(contentsOf: created.rootURL.appendingPathComponent("style.css"), encoding: .utf8) == "h1 { color: red; }")
        let status = try await runtime.status(projectID: created.projectID)
        #expect(status.revision == 1)
        #expect(status.manifestHash == created.manifestHash)
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
            argumentsJSON: "{\"projectID\":\"\(status.projectID)\",\"manifestHash\":\"\(status.manifestHash)\",\"accessMode\":\"private\"}"
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
        #expect(object["revision"] as? Int == status.revision)
        #expect(object["manifestHash"] as? String == status.manifestHash)
        #expect(object["fileCount"] as? Int == status.fileCount)
        #expect((object["totalBytes"] as? NSNumber)?.int64Value == status.totalBytes)
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
            argumentsJSON: "{\"projectID\":\"\(status.projectID)\",\"manifestHash\":\"\(status.manifestHash)\",\"accessMode\":\"private\"}"
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

        _ = try await runtime.updateDraft(
            projectID: status.projectID,
            expectedManifestHash: status.manifestHash,
            replacements: [:],
            edits: ["index.html": [(oldText: "Ready", newText: "Changed")]]
        )
        await #expect(throws: AgentToolError.self) {
            try await tool.preflight(call: call, context: context)
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
