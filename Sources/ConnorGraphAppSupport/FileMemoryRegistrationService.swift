import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphMemory

/// 把业务数据层的文件登记结果写成 L2 工作记忆：
/// - L2 实体（type=document，name=文件名）——让“找回上次那个文件”这类操作性问题可检索；
/// - append-only 语句：登记事实、版本/来源、模型从会话上下文推断的关联（人/项目/主题）。
/// 幂等：L2 按名称 upsert，语句按内容去重，重复登记不会产生重复实体或重复语句。
public struct FileMemoryRegistrationService: Sendable {
    public var facade: AppMemoryOSFacade
    public var store: FileArtifactStore

    public init(facade: AppMemoryOSFacade, store: FileArtifactStore) {
        self.facade = facade
        self.store = store
    }

    @discardableResult
    public func registerMemory(
        for record: FileArtifactRecord,
        context: String? = nil,
        associations: [String] = []
    ) throws -> MemoryOSL2UpdateEntitiesResult {
        let name = record.originalName
        var statements: [MemoryOSL2StatementUpdate] = [
            MemoryOSL2StatementUpdate(
                text: "文件 \(name)（fileID: \(record.fileID)）已登记，来源 \(record.source.rawValue)，提取状态 \(record.extractionStatus.rawValue)。",
                factType: "source_document"
            )
        ]
        if let context = context?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
            statements.append(MemoryOSL2StatementUpdate(text: context, factType: "other"))
        }
        for association in associations where !association.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statements.append(MemoryOSL2StatementUpdate(
                text: "文件 \(name) 与 \(association) 相关。",
                relation: GraphPredicate.relatedTo.rawValue,
                factType: "relationship"
            ))
        }
        let aliases = Self.aliases(for: record, associations: associations)
        let request = MemoryOSL2UpdateEntitiesRequest(entities: [
            MemoryOSL2EntityUpdate(
                name: name,
                type: "document",
                aliases: aliases,
                summary: record.summary ?? context,
                statements: statements
            )
        ])
        return try facade.updateMemoryOSL2Entities(request)
    }

    private static func aliases(for record: FileArtifactRecord, associations: [String]) -> String {
        var parts: [String] = []
        if let summary = record.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            parts.append(summary)
        }
        parts.append(contentsOf: associations.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        parts.append(record.fileID)
        return parts.joined(separator: ",")
    }
}
