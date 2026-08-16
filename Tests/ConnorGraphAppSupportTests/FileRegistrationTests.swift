import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport

@Suite("File Registration, Lookup, and Mail Reuse Tests")
struct FileRegistrationTests {
    private func makeHarness() throws -> (
        paths: AppStoragePaths,
        fileStore: FileArtifactStore,
        facade: AppMemoryOSFacade,
        attachmentStore: AppSessionAttachmentStore
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-file-reg-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let store = try SQLiteMemoryOSStore(path: paths.memoryOSDatabaseURL.path)
        try store.migrate()
        let facade = AppMemoryOSFacade(store: store)
        return (paths, FileArtifactStore(paths: paths), facade, AppSessionAttachmentStore(paths: paths))
    }

    private func context(sessionID: String = "session") -> AgentToolExecutionContext {
        AgentToolExecutionContext(
            runID: "run-file-reg",
            sessionID: sessionID,
            groupID: "group",
            userPrompt: "register file",
            toolCallID: UUID().uuidString,
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    }

    @Test func fileRegisterToolRegistersAttachmentAndWritesL2Memory() async throws {
        let (_, fileStore, facade, attachmentStore) = try makeHarness()
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-report-\(UUID().uuidString).txt")
        try "客服交接文件内容".write(to: source, atomically: true, encoding: .utf8)
        let manifest = try attachmentStore.importFile(at: source, sessionID: "session", now: Date())

        let memory = FileMemoryRegistrationService(facade: facade, store: fileStore)
        let tool = FileRegisterTool(attachmentStore: attachmentStore, fileStore: fileStore, memory: memory)
        let result = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"attachmentIDs":["\#(manifest.id)"],"context":"客服交接用的说明文件","associations":["客服"]}"#),
            context: context()
        )

        let json = try #require(result.contentJSON)
        #expect(json.contains(manifest.displayName))
        let record = try #require(fileStore.lookup(query: manifest.displayName, limit: 5).first)
        #expect(record.fileID.hasPrefix("file:"))

        // L2 记忆里应能按文件名/关键词搜到该文件（语句文本可检索）。
        let hits = try facade.searchMemoryOSContext(MemoryOSRetrievalQuery(
            text: "handoff-report",
            layers: [.l2],
            limit: 10
        ))
        #expect(hits.contains { $0.summary.contains("handoff-report") || $0.matchedText.contains("handoff-report") || $0.summary.contains(record.fileID) || $0.matchedText.contains(record.fileID) })
    }

    @Test func fileLookupToolReturnsRegisteredFile() async throws {
        let (_, fileStore, _, _) = try makeHarness()
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-file-src-\(UUID().uuidString).txt")
        try "客服文件正文".write(to: source, atomically: true, encoding: .utf8)
        let record = try fileStore.register(from: source, filename: "handoff.txt", source: .session, summary: "客服交接")

        let tool = FileLookupTool(store: fileStore)
        let result = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"query":"handoff"}"#),
            context: context()
        )
        let json = try #require(result.contentJSON)
        #expect(json.contains(record.fileID))
        #expect(result.citations.contains(record.fileID))
    }

    @Test func fileGetToolReturnsFullTextAttachment() async throws {
        let (_, fileStore, _, _) = try makeHarness()
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-file-src-\(UUID().uuidString).md")
        try "# 会议纪要\n\n- 第一项\n- 第二项".write(to: source, atomically: true, encoding: .utf8)
        let record = try fileStore.register(from: source, filename: "meeting.md", source: .generated, summary: "会议纪要")

        let tool = FileGetTool(store: fileStore)
        let result = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"fileID":"\#(record.fileID)"}"#),
            context: context()
        )
        #expect(result.toolName == "file_get")
        #expect(result.contentText.contains("会议纪要"))
        #expect(result.contentText.contains("# 会议纪要"))
        let json = try #require(result.contentJSON)
        #expect(json.contains(record.fileID))
        #expect(json.contains("localFileURL"))
    }

    @Test func fileGetToolRejectsUnknownFileID() async throws {
        let (_, fileStore, _, _) = try makeHarness()
        let tool = FileGetTool(store: fileStore)
        await #expect(throws: FileArtifactStoreError.self) {
            _ = try await tool.execute(
                arguments: try AgentToolArguments(json: #"{"fileID":"file:does-not-exist"}"#),
                context: context()
            )
        }
    }

    @Test func fileLookupToolSupportsPagingAndKindFilter() async throws {
        let (_, fileStore, _, _) = try makeHarness()
        for index in 1...3 {
            let source = FileManager.default.temporaryDirectory
                .appendingPathComponent("connor-file-src-\(UUID().uuidString).txt")
            try "内容 \(index)".write(to: source, atomically: true, encoding: .utf8)
            _ = try fileStore.register(from: source, filename: "note-\(index).txt", source: .session, summary: "文本附件")
        }
        let image = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-file-src-\(UUID().uuidString).png")
        try Data("png".utf8).write(to: image)
        _ = try fileStore.register(from: image, filename: "photo.png", source: .imported, summary: "图片")

        let tool = FileLookupTool(store: fileStore)
        let page0 = try await tool.execute(arguments: try AgentToolArguments(json: #"{"page":0,"limit":2}"#), context: context())
        let json0 = try #require(page0.contentJSON)
        #expect(json0.contains(#""total":4"#))
        #expect(json0.contains(#""hasMore":true"#))
        let page1 = try await tool.execute(arguments: try AgentToolArguments(json: #"{"page":1,"limit":2}"#), context: context())
        let json1 = try #require(page1.contentJSON)
        #expect(json1.contains(#""hasMore":false"#))
        let images = try await tool.execute(arguments: try AgentToolArguments(json: #"{"kind":"image"}"#), context: context())
        let jsonImage = try #require(images.contentJSON)
        #expect(jsonImage.contains(#""total":1"#))
        #expect(jsonImage.contains("photo.png"))
    }

    @Test func mailResolverResolvesFileIDFromFileStore() async throws {
        let (paths, fileStore, _, attachmentStore) = try makeHarness()
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-file-src-\(UUID().uuidString).txt")
        let data = Data("附件内容".utf8)
        try data.write(to: source)
        let record = try fileStore.register(from: source, filename: "attachment.txt", source: .session)

        let resolver = AppSessionOutboundMailAttachmentResolver(
            store: attachmentStore,
            fileStore: fileStore
        )
        let attachments = try await resolver.resolve(
            ids: [MailAttachmentID(rawValue: record.fileID)],
            sessionID: "session"
        )
        #expect(attachments.count == 1)
        #expect(attachments[0].filename == "attachment.txt")
        #expect(attachments[0].data == data)
        #expect(attachments[0].contentHash == record.sha256)
    }
}
