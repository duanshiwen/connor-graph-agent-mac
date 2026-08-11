import Foundation
import ConnorGraphAgent
import ConnorGraphCore

/// 把当前会话里的附件登记进业务文件库（FileStore）并写入 L2 工作记忆。
/// 用途：用户交来一个模型读不懂的文件时，登记它，让日后能按“文件名/主题/关联”找回并复用。
public struct FileRegisterTool: AgentTool {
    public let name = "file_register"
    public let description = "Register one or more current-session attachments into the durable business file store and record them in working memory, so the user can later retrieve the exact file (e.g. '上次给客服那个文件') and resend it as an attachment. Use this when the user hands over or transfers a file, especially when its content cannot be read. The original bytes are stored locally; only metadata and searchable context enter memory. Pass exact attachmentIDs from the current User Attachments section, never local paths or invented IDs."
    public let permission: AgentPermissionCapability = .proposeGraphWrite
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "attachmentIDs": .array(
            items: .string(description: "Exact attachment ID from the current User Attachments section."),
            description: "Current-session attachment IDs to register."
        ),
        "context": .string(description: "Optional one-sentence description of what this file is and why it matters, inferred from the conversation context."),
        "associations": .array(
            items: .string(description: "A related person, project, or topic name."),
            description: "Optional people/projects/topics this file relates to, inferred from the conversation context."
        )
    ], required: ["attachmentIDs"])

    private let attachmentStore: AppSessionAttachmentStore
    private let fileStore: FileArtifactStore
    private let memory: FileMemoryRegistrationService

    public init(
        attachmentStore: AppSessionAttachmentStore,
        fileStore: FileArtifactStore,
        memory: FileMemoryRegistrationService
    ) {
        self.attachmentStore = attachmentStore
        self.fileStore = fileStore
        self.memory = memory
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let attachmentIDs = (arguments.array("attachmentIDs") ?? arguments.array("attachment_ids") ?? [])
            .compactMap(\.stringValue)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !attachmentIDs.isEmpty else {
            throw AgentToolError.invalidArguments("attachmentIDs is required")
        }
        let contextText = arguments.string("context")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let associations = (arguments.array("associations") ?? [])
            .compactMap(\.stringValue)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let sessionRoot = attachmentStore.paths.sessionArtifactDirectories(sessionID: context.sessionID).root
        var records: [FileArtifactRecord] = []
        var failures: [String: String] = [:]
        for attachmentID in attachmentIDs {
            do {
                let manifest = try attachmentStore.loadManifest(sessionID: context.sessionID, attachmentID: attachmentID)
                let sourceURL = sessionRoot.appendingPathComponent(manifest.storedRelativePath)
                let record = try fileStore.register(
                    from: sourceURL,
                    filename: manifest.displayName,
                    source: .session,
                    summary: contextText
                )
                _ = try memory.registerMemory(for: record, context: contextText, associations: associations)
                records.append(record)
            } catch {
                failures[attachmentID] = String(describing: error)
            }
        }
        let payload: [String: Any] = [
            "registered": records.map(Self.json),
            "failed": failures
        ]
        let json = Self.renderJSON(payload)
        let readable: String
        if records.isEmpty {
            readable = "没有文件登记成功。\(failures.map { "\($0.key): \($0.value)" }.joined(separator: "; "))"
        } else {
            readable = records.map { "已登记 \($0.originalName)（\($0.fileID)，\($0.extractionStatus.rawValue)）" }.joined(separator: "\n")
        }
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: readable,
            contentJSON: json,
            citations: records.map(\.fileID)
        )
    }

    private static func json(_ record: FileArtifactRecord) -> [String: Any] {
        [
            "fileID": record.fileID,
            "originalName": record.originalName,
            "mimeType": record.mimeType ?? "",
            "byteCount": record.byteCount,
            "source": record.source.rawValue,
            "extractionStatus": record.extractionStatus.rawValue,
            "summary": record.summary ?? ""
        ]
    }

    private static func renderJSON(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}

/// 按名称/类型/来源/摘要查找已登记的业务文件。返回 fileID 与元数据，不返回字节。
public struct FileLookupTool: AgentTool {
    public let name = "file_lookup"
    public let description = "Search the durable business file store by filename, type, source, or summary context. Returns fileID and metadata so a previously registered file can be reattached (for example as a mail attachment). The original bytes stay local and are never passed to the model."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "query": .string(description: "Search terms: filename, type, source, or context summary."),
        "limit": .integer(description: "Optional maximum number of results. Defaults to 20, maximum 50.")
    ], required: ["query"])

    private let store: FileArtifactStore

    public init(store: FileArtifactStore) {
        self.store = store
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let query = arguments.string("query")?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            throw AgentToolError.invalidArguments("query is required")
        }
        let limit = min(max(arguments.int("limit") ?? 20, 1), 50)
        let records = store.lookup(query: query, limit: limit)
        let rows = records.map { record -> [String: Any] in
            [
                "fileID": record.fileID,
                "originalName": record.originalName,
                "mimeType": record.mimeType ?? "",
                "byteCount": record.byteCount,
                "source": record.source.rawValue,
                "extractionStatus": record.extractionStatus.rawValue,
                "summary": record.summary ?? "",
                "updatedAt": ISO8601DateFormatter().string(from: record.updatedAt)
            ]
        }
        let payload: [String: Any] = ["query": query, "count": rows.count, "files": rows]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            throw AgentToolError.invalidArguments("file_lookup failed to render results")
        }
        let readable: String
        if records.isEmpty {
            readable = "没有找到匹配的业务文件。"
        } else {
            readable = records.enumerated().map { index, record in
                "\(index + 1). \(record.originalName) [\(record.fileID)] (\(record.extractionStatus.rawValue), \(record.byteCount) bytes)"
            }.joined(separator: "\n")
        }
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: readable,
            contentJSON: json,
            citations: records.map(\.fileID)
        )
    }
}
