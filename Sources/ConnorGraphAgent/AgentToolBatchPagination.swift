import Foundation
import ConnorGraphCore

/// 分页列表 / 分批写操作的统一契约。
///
/// 所有带分页或每批数量上限的原生工具（会话列表、批量删除、技能列表等）都应复用这里的
/// 校验、契约文本与系统提示词规则，避免每个工具各自手写一套「读一批处理一批」的说明，
/// 从而压缩 Prompt 并保持行为一致。
public enum AgentToolBatchPagination {
    public static let defaultPageSize = 50
    public static let maxPageSize = 100
    /// 批量写操作单次调用最多处理的项目数。
    public static let defaultBatchSize = 50

    public static func validate(page: Int) throws {
        guard page >= 1 else {
            throw AgentToolError.invalidArguments("page must be at least 1")
        }
    }

    /// 校验并规范化 pageSize（缺省用默认值，超过上限抛错）。
    public static func validatedPageSize(
        _ value: Int?,
        default defaultPageSize: Int = Self.defaultPageSize,
        max maxPageSize: Int = Self.maxPageSize
    ) throws -> Int {
        let pageSize = value ?? defaultPageSize
        guard (1...maxPageSize).contains(pageSize) else {
            throw AgentToolError.invalidArguments("pageSize must be between 1 and \(maxPageSize)")
        }
        return pageSize
    }

    /// 列表/搜索工具 description 的统一分页契约文本。
    public static func paginationContract(
        listToolName: String,
        defaultPageSize: Int = Self.defaultPageSize,
        maxPageSize: Int = Self.maxPageSize
    ) -> String {
        """
        \(listToolName) pages by `page`/`pageSize` (default \(defaultPageSize), max \(maxPageSize)); every response contains `nextPage` when more pages remain. When complete coverage is needed, immediately call \(listToolName) again with `page` set to exactly the returned `nextPage` and keep every other input argument unchanged; repeat until `nextPage` is null. Never claim complete coverage before the final page.
        """
    }

    /// 批量写工具 description 的统一分批契约文本。
    public static func batchContract(
        toolName: String,
        maxItemsPerCall: Int = Self.defaultBatchSize
    ) -> String {
        """
        Each call accepts at most \(maxItemsPerCall) items; when more items must be processed, split them into batches of at most \(maxItemsPerCall) and call \(toolName) again until every item reports a terminal outcome. Never exceed the cap or invent identifiers.
        """
    }

    /// 系统提示词中的统一「读一批处理一批」规则（单一来源，各工具的说明只引用、不重写）。
    public static var promptRule: String {
        """
        - When a paginated list or search tool returns a non-null `nextPage` (equivalently `hasNextPage` is true) and the task requires complete coverage, process the returned batch completely, then immediately follow every exact non-null `nextPage` by calling the same tool again with `page` set to exactly that value and every other input argument unchanged; repeat until `nextPage` is null. Never claim full coverage before the final page.
        - When a batch write tool declares a per-call item cap (for example \"at most \(Self.defaultBatchSize) items per call\"), split the work into batches of at most that size and keep calling until every item is handled; never exceed the cap or fabricate identifiers.
        """
    }
}
