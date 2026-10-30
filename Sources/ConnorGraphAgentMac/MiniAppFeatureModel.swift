import Foundation
import Observation
import ConnorGraphBase
import ConnorGraphAppSupport

// MARK: - 小程序列表数据模型

/// 小程序所在位置：本机（本地注册库）或云端（服务器目录）。
public enum MiniAppSource: String, Sendable {
    case local
    case cloud
}

/// 可见范围（使用范围）。
public enum MiniAppScope: String, Sendable {
    case privateOnly = "private"   // 仅自己使用
    case shared = "shared"         // 共享给好友
    case publicOpen = "public"     // 公开共享

    public var badgeText: String {
        switch self {
        case .privateOnly: return "仅自己"
        case .shared: return "好友共享"
        case .publicOpen: return "公开共享"
        }
    }
}

/// 小程序列表项（本机 + 云端汇总后的统一条目）。
public struct MiniAppEntry: Identifiable, Equatable, Sendable {
    public let appID: String
    public let name: String
    public let domain: String
    public let purpose: String
    public let scope: MiniAppScope
    public let source: MiniAppSource
    public let isOwned: Bool          // 我创建 / 我可用
    public let methodCount: Int
    public let tableCount: Int
    public let packageVersion: Int
    public let riskLevel: String
    public let ownerName: String
    public let updatedAt: String

    public var id: String { appID }

    public var sourceBadge: String { source == .local ? "本机" : "云端" }
    public var scopeBadge: String { scope.badgeText }
    public var relationBadge: String { isOwned ? "我创建" : "我可用" }
    public var displayUpdatedAt: String { String(updatedAt.prefix(10)) }
}

/// 小程序详情（详情页：功能说明 + 汇总提示）。
public struct MiniAppDetail: Equatable, Sendable {
    public let appID: String
    public let name: String
    public let domain: String
    public let purpose: String
    public let scope: MiniAppScope
    public let source: MiniAppSource
    public let isOwned: Bool
    public let ownerName: String
    public let riskLevel: String
    public let sdkVersion: Int
    public let capabilities: [String]
    public let methodCount: Int
    public let tableCount: Int
    public let dataTableCount: Int
    public let methods: [String]
    public let tableNames: [String]
    public let guideSummary: String
    public let guideNotes: [String]
    public let updatedAt: String

    public var sourceBadge: String { source == .local ? "本机" : "云端" }
    public var scopeBadge: String { scope.badgeText }
    public var relationBadge: String { isOwned ? "我创建" : "我可用" }
}

// MARK: - 小程序列表 FeatureModel（Mac 端）

/// 「小程序」工作区列表模型：
/// - 数据源 = 本机注册库（BaseLibraryStore.listApps）+ 云端目录（base.app.list）；
/// - 按 appID 去重（本机优先），本机全量加载、云端分页加载；
/// - 列表项标注 本机/云端、仅自己/共享、我创建/我可用；
/// - 详情页展示 功能说明 + 汇总提示（方法/表/数据快照/使用说明）。
@MainActor
@Observable
public final class MiniAppFeatureModel {
    public private(set) var entries: [MiniAppEntry] = []
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var cloudPage = 1
    public private(set) var cloudTotal = 0
    public private(set) var cloudHasMore = false
    public private(set) var localCount = 0
    public private(set) var errorMessage: String?
    public private(set) var cloudUnavailable = false
    /// 当前筛选关键词（由统一搜索注入，列表内不展示搜索框）。
    /// 非空时本机本地过滤、云端服务端过滤，仅展示携带该关键词的小程序。
    public var searchText = ""
    public var selectedAppID: String?
    public private(set) var selectedDetail: MiniAppDetail?
    public private(set) var detailIsLoading = false
    public private(set) var detailErrorMessage: String?

    private let library: BaseLibraryStore?
    private let cloudClient: BaseCloudAPIClient?
    private var allLocal: [MiniAppEntry] = []
    private var allCloud: [MiniAppEntry] = []
    private var detailTask: Task<Void, Never>?
    private var reloadGeneration = 0
    private var detailGeneration = 0
    private var loadedOnce = false

    public init(library: BaseLibraryStore?, cloudClient: BaseCloudAPIClient?) {
        self.library = library
        self.cloudClient = cloudClient
    }
    public func importReviewedPackage(_ json: String) throws {
        guard let library else { throw BasePackageImporter.ImportError.invalid("本机小程序库不可用。") }
        let id = try BasePackageImporter.install(json, library: library)
        reload()
        select(appID: id)
    }

    // MARK: 首次加载 / 刷新

    public func loadIfNeeded() {
        guard !isLoading, !hasLoaded else { return }
        reload()
    }

    public func reload() {
        reloadGeneration += 1
        let generation = reloadGeneration
        isLoadingMore = false
        let query = trimmedQuery
        isLoading = true
        errorMessage = nil
        cloudUnavailable = false
        allLocal = loadLocalEntries(query: query)
        allCloud = []
        cloudPage = 1
        cloudTotal = 0
        cloudHasMore = false
        publishMerged()
        guard let cloudClient else {
            isLoading = false
            loadedOnce = true
            publishMerged()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            await self.fetchCloudPage(client: cloudClient, page: 1, query: query, generation: generation)
            guard generation == self.reloadGeneration else { return }
            self.isLoading = false
            self.loadedOnce = true
            self.publishMerged()
        }
    }

    public func loadMore() {
        guard let cloudClient, cloudHasMore, !isLoading, !isLoadingMore, !hasLoadedAllCloud else { return }
        isLoadingMore = true
        let nextPage = cloudPage + 1
        let generation = reloadGeneration
        let query = trimmedQuery
        Task { [weak self] in
            guard let self else { return }
            await self.fetchCloudPage(client: cloudClient, page: nextPage, query: query, generation: generation)
            guard generation == self.reloadGeneration else { return }
            self.isLoadingMore = false
            self.publishMerged()
        }
    }

    /// 统一搜索入口：设置筛选关键词并立即重拉（本机本地过滤，云端服务端过滤）。
    public func applySearchQuery(_ query: String) {
        searchText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        reload()
    }

    /// 清除筛选关键词并恢复完整列表（列表页 banner 的清除按钮）。
    public func clearSearch() {
        guard !trimmedQuery.isEmpty else { return }
        searchText = ""
        reload()
    }

    // MARK: 选中 + 详情

    public func select(appID: String) {
        guard selectedAppID != appID || selectedDetail == nil && !detailIsLoading else { return }
        detailGeneration += 1
        let generation = detailGeneration
        detailTask?.cancel()
        selectedAppID = appID
        selectedDetail = nil
        detailErrorMessage = nil
        detailIsLoading = true
        detailTask = Task { [weak self] in
            guard let self else { return }
            let detail = await self.loadDetail(appID: appID, generation: generation)
            guard generation == self.detailGeneration, self.selectedAppID == appID, !Task.isCancelled else { return }
            self.selectedDetail = detail
            self.detailIsLoading = false
        }
    }

    // MARK: 内部实现

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasLoaded: Bool {
        loadedOnce
    }

    private var hasLoadedAllCloud: Bool {
        allCloud.count >= cloudTotal
    }

    private func loadLocalEntries(query: String, updateCount: Bool = true) -> [MiniAppEntry] {
        guard let library else { return [] }
        do {
            let cards = try library.listApps(query: query.isEmpty ? nil : query)
            if updateCount { localCount = cards.count }
            return cards.compactMap { card in
                guard let appID = card["appID"] as? String else { return nil }
                let visibility = (card["visibility"] as? String) ?? "private"
                let tableCount: Int
                if let schema = try? library.currentSchemaObject(appID: appID), let tables = schema["tables"] as? [[String: Any]] {
                    tableCount = tables.count
                } else {
                    tableCount = 0
                }
                return MiniAppEntry(
                    appID: appID,
                    name: (card["name"] as? String) ?? appID,
                    domain: (card["domain"] as? String) ?? "",
                    purpose: (card["purpose"] as? String) ?? "",
                    scope: MiniAppScope(rawValue: visibility) ?? .privateOnly,
                    source: .local,
                    isOwned: true,
                    methodCount: (card["methods"] as? [[String: Any]])?.count ?? 0,
                    tableCount: tableCount,
                    packageVersion: Self.intValue(card["packageVersion"]) ?? 0,
                    riskLevel: (card["riskLevel"] as? String) ?? "low",
                    ownerName: "",
                    updatedAt: (card["updatedAt"] as? String) ?? ""
                )
            }
        } catch {
            if errorMessage == nil {
                errorMessage = "本机小程序读取失败：\(error.localizedDescription)"
            }
            return []
        }
    }

    private func fetchCloudPage(client: BaseCloudAPIClient, page: Int, query: String, generation: Int) async {
        do {
            let result = try await client.listApps(query: query, page: page, limit: 20)
            guard generation == reloadGeneration, query == trimmedQuery else { return }
            cloudPage = result.page
            cloudTotal = result.total
            cloudHasMore = result.hasMore
            let remoteIDs = Set(allCloud.map(\.appID))
            let localIDs = Set(allLocal.map(\.appID))
            for item in result.items where !remoteIDs.contains(item.appId) && !localIDs.contains(item.appId) {
                allCloud.append(MiniAppEntry(
                    appID: item.appId,
                    name: item.name.isEmpty ? item.appId : item.name,
                    domain: item.domain,
                    purpose: item.purpose,
                    scope: MiniAppScope(rawValue: item.visibility) ?? .publicOpen,
                    source: .cloud,
                    isOwned: item.isOwner,
                    methodCount: item.methodCount,
                    tableCount: item.tableCount,
                    packageVersion: item.packageVersion,
                    riskLevel: "low",
                    ownerName: item.ownerName,
                    updatedAt: item.updatedAt
                ))
            }
        } catch {
            guard generation == reloadGeneration, query == trimmedQuery else { return }
            cloudUnavailable = true
            if errorMessage == nil {
                errorMessage = "云端目录暂不可用：\(error.localizedDescription)"
            }
        }
    }

    private func publishMerged() {
        var merged = allLocal
        let localIDs = Set(allLocal.map(\.appID))
        for cloud in allCloud where !localIDs.contains(cloud.appID) {
            merged.append(cloud)
        }
        // 同一 appID 云端重复项只保留首个（fetchCloudPage 已按页去重，这里兜底）。
        var seen = Set<String>()
        entries = merged.filter { seen.insert($0.appID).inserted }
        // 选中项若还在列表里则保持选中，否则清空。
        if !isLoading, !isLoadingMore, let selectedAppID, !entries.contains(where: { $0.appID == selectedAppID }) {
            detailGeneration += 1
            detailTask?.cancel()
            self.selectedAppID = nil
            selectedDetail = nil
            detailIsLoading = false
        }
    }

    private func loadDetail(appID: String, generation: Int) async -> MiniAppDetail? {
        detailErrorMessage = nil
        let entry = entries.first { $0.appID == appID }
        if let entry, entry.source == .local, let library {
            return buildLocalDetail(entry: entry, library: library)
        }
        guard let cloudClient else {
            detailErrorMessage = "该小程序无可用详情源"
            return nil
        }
        do {
            let detail = try await cloudClient.appDetail(appID: appID)
            guard generation == detailGeneration, selectedAppID == appID, !Task.isCancelled else { return nil }
            let guideSummary = Self.guideSummary(from: detail.guide ?? [:])
            return MiniAppDetail(
                appID: detail.appId,
                name: detail.name.isEmpty ? detail.appId : detail.name,
                domain: detail.domain,
                purpose: detail.purpose,
                scope: MiniAppScope(rawValue: detail.visibility) ?? .publicOpen,
                source: .cloud,
                isOwned: detail.isOwner,
                ownerName: detail.ownerName,
                riskLevel: detail.riskLevel,
                sdkVersion: detail.sdkVersion,
                capabilities: detail.capabilities,
                methodCount: detail.methodCount,
                tableCount: detail.tableCount,
                dataTableCount: detail.dataTableCount,
                methods: detail.methods,
                tableNames: [],
                guideSummary: guideSummary.summary,
                guideNotes: guideSummary.notes,
                updatedAt: detail.updatedAt
            )
        } catch {
            guard generation == detailGeneration, selectedAppID == appID, !Task.isCancelled else { return nil }
            detailErrorMessage = "云端详情读取失败：\(error.localizedDescription)"
            return nil
        }
    }

    private func buildLocalDetail(entry: MiniAppEntry, library: BaseLibraryStore) -> MiniAppDetail? {
        do {
            let card = try library.appCard(appID: entry.appID, includeGuide: true)
            let schema = (try? library.currentSchemaObject(appID: entry.appID)) ?? [:]
            let tables = (schema["tables"] as? [[String: Any]]) ?? []
            let tableNames = tables.compactMap { $0["name"] as? String }
            let methods = (card?["methods"] as? [[String: Any]]) ?? []
            let methodNames = methods.compactMap { $0["name"] as? String }
            let guide = (card?["guide"] as? [String: Any]) ?? [:]
            let summary = Self.guideSummary(from: guide)
            let dataTableCount = Self.dataTableCount(from: schema)
            return MiniAppDetail(
                appID: entry.appID,
                name: entry.name,
                domain: entry.domain,
                purpose: entry.purpose,
                scope: entry.scope,
                source: .local,
                isOwned: true,
                ownerName: "",
                riskLevel: entry.riskLevel,
                sdkVersion: Self.intValue(card?["sdkVersion"]) ?? 1,
                capabilities: (card?["requiredCapabilities"] as? [String]) ?? [],
                methodCount: methods.count,
                tableCount: tables.count,
                dataTableCount: dataTableCount,
                methods: methodNames,
                tableNames: tableNames,
                guideSummary: summary.summary,
                guideNotes: summary.notes,
                updatedAt: entry.updatedAt
            )
        } catch {
            detailErrorMessage = "本机详情读取失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 从 guide（[String: Any] 或 [String: ConnorJSONValue]）提取汇总提示。
    private static func guideSummary(from raw: [String: Any]) -> (summary: String, notes: [String]) {
        if let usage = raw["usage"] as? [String: Any] {
            var body = usage; body.removeValue(forKey: "notes"); body.removeValue(forKey: "tips")
            if let data = try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys]) { return (String(decoding: data, as: UTF8.self), guideNotes(from: usage)) }
        }
        let summaryKeys = ["usage", "overview", "summary", "intro", "description", "说明", "简介", "用途"]
        for key in summaryKeys {
            if let value = raw[key] as? String, !value.isEmpty {
                return (value, guideNotes(from: raw))
            }
        }
        return ("暂无使用说明", guideNotes(from: raw))
    }

    private static func guideSummary(from raw: [String: ConnorJSONValue]) -> (summary: String, notes: [String]) {
        if case .object(let usage) = raw["usage"] {
            var body = usage; body.removeValue(forKey: "notes"); body.removeValue(forKey: "tips")
            if let data = try? JSONEncoder().encode(body) { return (String(decoding: data, as: UTF8.self), guideNotes(from: usage)) }
        }
        let summaryKeys = ["usage", "overview", "summary", "intro", "description", "说明", "简介", "用途"]
        for key in summaryKeys {
            if case .string(let value) = raw[key], !value.isEmpty {
                return (value, guideNotes(from: raw))
            }
        }
        return ("暂无使用说明", guideNotes(from: raw))
    }

    private static func guideNotes(from raw: [String: Any]) -> [String] {
        var notes: [String] = []
        if let list = raw["notes"] as? [Any] {
            notes = list.compactMap { $0 as? String }.filter { !$0.isEmpty }
        }
        if let list = raw["tips"] as? [Any] {
            notes.append(contentsOf: list.compactMap { $0 as? String }.filter { !$0.isEmpty })
        }
        return notes
    }

    private static func guideNotes(from raw: [String: ConnorJSONValue]) -> [String] {
        var notes: [String] = []
        if case .array(let list) = raw["notes"] {
            notes = list.compactMap { value in if case .string(let s) = value { return s }; return nil }.filter { !$0.isEmpty }
        }
        if case .array(let list) = raw["tips"] {
            notes.append(contentsOf: list.compactMap { value in if case .string(let s) = value { return s }; return nil }.filter { !$0.isEmpty })
        }
        return notes
    }

    /// 数据快照 {tables:{name: rows}} 的表数汇总。
    private static func dataTableCount(from schema: [String: Any]) -> Int {
        if let data = schema["data"] as? [String: Any], let tables = data["tables"] as? [String: Any] {
            return tables.count
        }
        return 0
    }

    /// 聚合搜索入口：按关键词返回本机 + 云端小程序结果（最多拉两页云端）。
    func searchMatches(query: String) async -> [GlobalSearchMiniAppResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [GlobalSearchMiniAppResult] = []
        if library != nil {
            for entry in loadLocalEntries(query: trimmed, updateCount: false) {
                results.append(GlobalSearchMiniAppResult(
                    appID: entry.appID, name: entry.name, purpose: entry.purpose,
                    sourceBadge: entry.sourceBadge, scopeBadge: entry.scopeBadge, relationBadge: entry.relationBadge
                ))
            }
        }
        if let cloudClient {
            for page in 1...2 {
                do {
                    let pageResult = try await cloudClient.listApps(query: trimmed, page: page, limit: 20)
                    for item in pageResult.items where !results.contains(where: { $0.appID == item.appId }) {
                        results.append(GlobalSearchMiniAppResult(
                            appID: item.appId,
                            name: item.name.isEmpty ? item.appId : item.name,
                            purpose: item.purpose,
                            sourceBadge: "云端",
                            scopeBadge: MiniAppScope(rawValue: item.visibility)?.badgeText ?? "公开共享",
                            relationBadge: item.isOwner ? "我创建" : "我可用"
                        ))
                    }
                    if !pageResult.hasMore { break }
                } catch {
                    break
                }
            }
        }
        return results
    }

    /// SQLite 行值（Int64）到 Int 的安全转换。
    static func intValue(_ value: Any?) -> Int? {
        if let v = value as? Int { return v }
        if let v = value as? Int64 { return Int(v) }
        if let v = value as? NSNumber { return v.intValue }
        return nil
    }
}
