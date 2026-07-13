import Foundation
import Combine

public struct CloudMarketplaceCategory: Decodable, Sendable, Equatable, Identifiable {
    public var id: String; public var name: String; public var parentID: String?; public var icon: String?
    public init(id: String, name: String, parentID: String? = nil, icon: String? = nil) { self.id = id; self.name = name; self.parentID = parentID; self.icon = icon }
    private enum CodingKeys: String, CodingKey { case id, name, parentID, icon, slug, localizedNames }
    public init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = try c.decode(String.self, forKey: .id); parentID = try c.decodeIfPresent(String.self, forKey: .parentID); icon = try c.decodeIfPresent(String.self, forKey: .icon); let names = try c.decodeIfPresent([String: String].self, forKey: .localizedNames) ?? [:]; name = try c.decodeIfPresent(String.self, forKey: .name) ?? Self.localized(names) ?? c.decodeIfPresent(String.self, forKey: .slug) ?? id }
    private static func localized(_ names: [String: String]) -> String? { let locale = Locale.current.identifier.replacingOccurrences(of: "_", with: "-"); return names[locale] ?? names[String(locale.prefix(2))] ?? names["zh-CN"] ?? names["en"] ?? names.values.first }
}
public struct CloudMarketplaceBanner: Codable, Sendable, Equatable, Identifiable { public var id: String; public var title: String; public var subtitle: String?; public var imageURL: String?; public var actionURL: String?; public init(id: String, title: String, subtitle: String? = nil, imageURL: String? = nil, actionURL: String? = nil) { self.id = id; self.title = title; self.subtitle = subtitle; self.imageURL = imageURL; self.actionURL = actionURL } }
public struct CloudMarketplaceKnowledgeBase: Codable, Sendable, Equatable, Identifiable { public var id: String; public var name: String; public var description: String?; public var categoryID: String?; public var subscriberCount: Int; public var subscribed: Bool; public var publicationStatus: String?; public init(id: String, name: String, description: String? = nil, categoryID: String? = nil, subscriberCount: Int = 0, subscribed: Bool = false, publicationStatus: String? = nil) { self.id = id; self.name = name; self.description = description; self.categoryID = categoryID; self.subscriberCount = subscriberCount; self.subscribed = subscribed; self.publicationStatus = publicationStatus } }
public struct CloudMarketplaceSection: Decodable, Sendable, Equatable, Identifiable {
    public var id: String; public var title: String; public var layout: String; public var knowledgeBases: [CloudMarketplaceKnowledgeBase]
    public init(id: String, title: String, layout: String, knowledgeBases: [CloudMarketplaceKnowledgeBase]) { self.id = id; self.title = title; self.layout = layout; self.knowledgeBases = knowledgeBases }
    private enum CodingKeys: String, CodingKey { case id, title, layout, sectionType, knowledgeBases }
    public init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = try c.decode(String.self, forKey: .id); if let value = try? c.decode(String.self, forKey: .title) { title = value } else { let names = try c.decode([String: String].self, forKey: .title); title = names["zh-CN"] ?? names["en"] ?? names.values.first ?? id }; layout = try c.decodeIfPresent(String.self, forKey: .layout) ?? c.decode(String.self, forKey: .sectionType); knowledgeBases = try c.decodeIfPresent([CloudMarketplaceKnowledgeBase].self, forKey: .knowledgeBases) ?? [] }
}
public struct CloudMarketplaceHome: Decodable, Sendable, Equatable { public var categories: [CloudMarketplaceCategory]; public var banners: [CloudMarketplaceBanner]; public var sections: [CloudMarketplaceSection]; public init(categories: [CloudMarketplaceCategory], banners: [CloudMarketplaceBanner] = [], sections: [CloudMarketplaceSection]) { self.categories = categories; self.banners = banners; self.sections = sections } }
public struct CloudMarketplaceSearchRequest: Codable, Sendable, Equatable { public var query: String; public var categoryID: String?; public var limit: Int; public init(query: String, categoryID: String? = nil, limit: Int = 30) { self.query = query; self.categoryID = categoryID; self.limit = limit } }
public struct CloudKnowledgeAnswerRequest: Codable, Sendable, Equatable { public var requestID: String; public var query: String; public var knowledgeBaseIDs: [String]; public var contextBudget: Int; public var limit: Int; public init(requestID: String = UUID().uuidString, query: String, knowledgeBaseIDs: [String], contextBudget: Int = 8_000, limit: Int = 20) { self.requestID = requestID; self.query = query; self.knowledgeBaseIDs = knowledgeBaseIDs; self.contextBudget = contextBudget; self.limit = limit }; private enum CodingKeys: String, CodingKey { case requestID = "requestId", query, knowledgeBaseIDs, contextBudget = "contextBudgetBytes", limit } }
public struct CloudKnowledgeAnswerPartition: Codable, Sendable, Equatable { public var layer: CloudKnowledgeLayer; public var results: [CloudKnowledgeSearchHit]; public init(layer: CloudKnowledgeLayer, results: [CloudKnowledgeSearchHit]) { self.layer = layer; self.results = results } }
public struct CloudKnowledgeAnswerResponse: Codable, Sendable, Equatable {
    public var requestID: String; public var partitions: [CloudKnowledgeAnswerPartition]; public var returnedBytes: Int?; public var knowledgeSequence: Int?
    public init(requestID: String, partitions: [CloudKnowledgeAnswerPartition], returnedBytes: Int? = nil, knowledgeSequence: Int? = nil) { self.requestID = requestID; self.partitions = partitions; self.returnedBytes = returnedBytes; self.knowledgeSequence = knowledgeSequence }
    private enum CodingKeys: String, CodingKey { case requestID = "requestId", partitions, returnedBytes, knowledgeSequence, l2, l3, l4 }
    public init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); requestID = try c.decode(String.self, forKey: .requestID); returnedBytes = try c.decodeIfPresent(Int.self, forKey: .returnedBytes); knowledgeSequence = try c.decodeIfPresent(Int.self, forKey: .knowledgeSequence); if let direct = try c.decodeIfPresent([CloudKnowledgeAnswerPartition].self, forKey: .partitions) { partitions = direct } else { partitions = [.init(layer: .l2, results: try c.decodeIfPresent([CloudKnowledgeSearchHit].self, forKey: .l2) ?? []), .init(layer: .l3, results: try c.decodeIfPresent([CloudKnowledgeSearchHit].self, forKey: .l3) ?? []), .init(layer: .l4, results: try c.decodeIfPresent([CloudKnowledgeSearchHit].self, forKey: .l4) ?? [])] } }
    public func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(requestID, forKey: .requestID); try c.encode(partitions, forKey: .partitions); try c.encodeIfPresent(returnedBytes, forKey: .returnedBytes); try c.encodeIfPresent(knowledgeSequence, forKey: .knowledgeSequence) }
}

public protocol CloudKnowledgeMarketplaceAPI: Sendable {
    func home() async throws -> CloudMarketplaceHome
    func categories() async throws -> [CloudMarketplaceCategory]
    func search(_ request: CloudMarketplaceSearchRequest) async throws -> [CloudMarketplaceKnowledgeBase]
    func detail(id: String) async throws -> CloudMarketplaceKnowledgeBase
    func subscribe(id: String) async throws
    func unsubscribe(id: String) async throws
    func answer(_ request: CloudKnowledgeAnswerRequest) async throws -> CloudKnowledgeAnswerResponse
}

public struct CloudKnowledgeAnswerCacheEntry: Sendable, Equatable {
    public var response: CloudKnowledgeAnswerResponse; public var knowledgeBaseIDs: [String]
    public init(response: CloudKnowledgeAnswerResponse, knowledgeBaseIDs: [String]) { self.response = response; self.knowledgeBaseIDs = knowledgeBaseIDs }
}

public actor CloudKnowledgeAuthorizationCache {
    private var authorized = Set<String>(); private var answers: [String: CloudKnowledgeAnswerCacheEntry] = [:]
    public init() {}
    public func authorize(_ id: String) { authorized.insert(id) }
    public func revoke(_ id: String) { authorized.remove(id); answers = answers.filter { !$0.value.knowledgeBaseIDs.contains(id) } }
    public func isAuthorized(_ id: String) -> Bool { authorized.contains(id) }
    public func value(key: String) -> CloudKnowledgeAnswerResponse? { answers[key]?.response }
    public func set(_ value: CloudKnowledgeAnswerResponse, key: String, knowledgeBaseIDs: [String]) { answers[key] = .init(response: value, knowledgeBaseIDs: knowledgeBaseIDs) }
    public func clear() { authorized.removeAll(); answers.removeAll() }
}

@MainActor public final class CloudKnowledgeMarketplaceStore: ObservableObject {
    @Published public private(set) var home = CloudMarketplaceHome(categories: [], banners: [], sections: [])
    @Published public private(set) var searchResults: [CloudMarketplaceKnowledgeBase] = []; @Published public private(set) var selected: CloudMarketplaceKnowledgeBase?; @Published public private(set) var isLoading = false; @Published public private(set) var errorMessage: String?
    private let api: any CloudKnowledgeMarketplaceAPI; private let cache: CloudKnowledgeAuthorizationCache
    public init(api: any CloudKnowledgeMarketplaceAPI, cache: CloudKnowledgeAuthorizationCache = .init()) { self.api = api; self.cache = cache }
    public func loadHome() async { await perform { self.home = try await self.api.home(); for base in self.home.sections.flatMap(\.knowledgeBases) where base.subscribed { await self.cache.authorize(base.id) } } }
    public func search(query: String, categoryID: String? = nil) async { await perform { self.searchResults = try await self.api.search(.init(query: query, categoryID: categoryID)) } }
    public func loadDetail(id: String) async { await perform { self.selected = try await self.api.detail(id: id) } }
    public func subscribe(id: String) async { await perform { try await self.api.subscribe(id: id); await self.cache.authorize(id); if self.selected?.id == id { self.selected?.subscribed = true } } }
    public func unsubscribe(id: String) async { await cache.revoke(id); if selected?.id == id { selected?.subscribed = false }; do { try await api.unsubscribe(id: id) } catch { errorMessage = error.localizedDescription } }
    public func clearSession() async { home = .init(categories: [], banners: [], sections: []); searchResults = []; selected = nil; errorMessage = nil; await cache.clear() }
    private func perform(_ action: @escaping () async throws -> Void) async { isLoading = true; errorMessage = nil; defer { isLoading = false }; do { try await action() } catch { errorMessage = error.localizedDescription } }
}

public actor CloudKnowledgeConsumptionClient {
    private let api: any CloudKnowledgeMarketplaceAPI; private let cache: CloudKnowledgeAuthorizationCache
    public init(api: any CloudKnowledgeMarketplaceAPI, cache: CloudKnowledgeAuthorizationCache) { self.api = api; self.cache = cache }
    public func answer(_ request: CloudKnowledgeAnswerRequest) async throws -> CloudKnowledgeAnswerResponse {
        for id in request.knowledgeBaseIDs where await !cache.isAuthorized(id) { throw CloudKnowledgeError.server(status: 403, code: "subscription_required", message: "知识库订阅已失效。") }
        let key = request.knowledgeBaseIDs.sorted().joined(separator: ",") + "|" + request.query + "|\(request.contextBudget)|\(request.limit)"
        if let cached = await cache.value(key: key) { return cached }
        let response = try await api.answer(request); await cache.set(response, key: key, knowledgeBaseIDs: request.knowledgeBaseIDs); return response
    }
}
