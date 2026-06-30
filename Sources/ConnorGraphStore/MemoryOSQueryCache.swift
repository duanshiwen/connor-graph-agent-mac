import Foundation
import ConnorGraphCore

/// In-memory LRU cache for frequently accessed Memory OS queries.
/// Thread-safe for concurrent access.
public final class MemoryOSQueryCache: @unchecked Sendable {
    
    // MARK: - Cache Entry
    
    private final class CacheEntry<T> {
        let value: T
        let createdAt: Date
        let ttl: TimeInterval
        
        init(value: T, ttl: TimeInterval) {
            self.value = value
            self.createdAt = Date()
            self.ttl = ttl
        }
        
        var isExpired: Bool {
            Date().timeIntervalSince(createdAt) > ttl
        }
    }
    
    // MARK: - LRU Cache
    
    private final class LRUCache<Key: Hashable, Value> {
        private var cache: [Key: CacheEntry<Value>] = [:]
        private var accessOrder: [Key] = []
        let capacity: Int
        private let lock = NSLock()
        
        init(capacity: Int) {
            self.capacity = capacity
        }
        
        func get(_ key: Key) -> Value? {
            lock.lock()
            defer { lock.unlock() }
            
            guard let entry = cache[key], !entry.isExpired else {
                cache.removeValue(forKey: key)
                accessOrder.removeAll { $0 == key }
                return nil
            }
            
            // Move to end (most recently used)
            accessOrder.removeAll { $0 == key }
            accessOrder.append(key)
            
            return entry.value
        }
        
        func set(_ key: Key, value: Value, ttl: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            
            // Remove if already exists
            if cache[key] != nil {
                accessOrder.removeAll { $0 == key }
            }
            
            // Evict if at capacity
            while cache.count >= capacity, let oldest = accessOrder.first {
                cache.removeValue(forKey: oldest)
                accessOrder.removeFirst()
            }
            
            cache[key] = CacheEntry(value: value, ttl: ttl)
            accessOrder.append(key)
        }
        
        func invalidate(_ key: Key) {
            lock.lock()
            defer { lock.unlock() }
            
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
        
        func invalidateAll() {
            lock.lock()
            defer { lock.unlock() }
            
            cache.removeAll()
            accessOrder.removeAll()
        }
        
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return cache.count
        }
    }
    
    // MARK: - Cache Instances
    
    /// Current user profile cache (long TTL, rarely changes)
    private let profileCache = LRUCache<String, [String]>(capacity: 1)
    
    /// L2 nodes cache (medium TTL)
    private let l2NodesCache = LRUCache<String, [MemoryOSNode]>(capacity: 10)
    
    /// L2 statements cache (medium TTL)
    private let l2StatementsCache = LRUCache<String, [MemoryOSStatement]>(capacity: 10)
    
    /// L4 entity expansion cache (short TTL, expensive to compute)
    private let entityExpansionCache = LRUCache<String, [MemoryOSL4ExpansionHit]>(capacity: 50)
    
    /// FTS5 search results cache (very short TTL)
    private let ftsSearchCache = LRUCache<String, [String]>(capacity: 100)
    
    /// Context query cache (short TTL)
    private let contextCache = LRUCache<String, [String]>(capacity: 50)
    
    // MARK: - TTL Constants
    
    public enum TTL {
        /// Current user profile: 5 minutes
        public static let profile: TimeInterval = 300
        /// L2 nodes/statements: 2 minutes
        public static let l2Data: TimeInterval = 120
        /// L4 entity expansion: 1 minute
        public static let entityExpansion: TimeInterval = 60
        /// FTS5 search results: 30 seconds
        public static let ftsSearch: TimeInterval = 30
        /// Context queries: 30 seconds
        public static let context: TimeInterval = 30
    }
    
    // MARK: - Singleton
    
    public static let shared = MemoryOSQueryCache()
    
    private init() {}
    
    // MARK: - Profile Cache
    
    public func getCachedProfile() -> [String]? {
        profileCache.get("current_user")
    }
    
    public func setCachedProfile(_ profile: [String]) {
        profileCache.set("current_user", value: profile, ttl: TTL.profile)
    }
    
    public func invalidateProfile() {
        profileCache.invalidate("current_user")
    }
    
    // MARK: - L2 Cache
    
    public func getCachedL2Nodes(key: String) -> [MemoryOSNode]? {
        l2NodesCache.get(key)
    }
    
    public func setCachedL2Nodes(_ nodes: [MemoryOSNode], key: String) {
        l2NodesCache.set(key, value: nodes, ttl: TTL.l2Data)
    }
    
    public func getCachedL2Statements(key: String) -> [MemoryOSStatement]? {
        l2StatementsCache.get(key)
    }
    
    public func setCachedL2Statements(_ statements: [MemoryOSStatement], key: String) {
        l2StatementsCache.set(key, value: statements, ttl: TTL.l2Data)
    }
    
    // MARK: - Entity Expansion Cache
    
    public func getCachedEntityExpansion(entityName: String, depth: Int, limit: Int) -> [MemoryOSL4ExpansionHit]? {
        let key = "\(entityName):\(depth):\(limit)"
        return entityExpansionCache.get(key)
    }
    
    public func setCachedEntityExpansion(_ hits: [MemoryOSL4ExpansionHit], entityName: String, depth: Int, limit: Int) {
        let key = "\(entityName):\(depth):\(limit)"
        entityExpansionCache.set(key, value: hits, ttl: TTL.entityExpansion)
    }
    
    // MARK: - FTS Search Cache
    
    public func getCachedFTSSearch(query: String, limit: Int) -> [String]? {
        let key = "\(query):\(limit)"
        return ftsSearchCache.get(key)
    }
    
    public func setCachedFTSSearch(_ results: [String], query: String, limit: Int) {
        let key = "\(query):\(limit)"
        ftsSearchCache.set(key, value: results, ttl: TTL.ftsSearch)
    }
    
    // MARK: - Context Cache
    
    public func getCachedContext(query: String) -> [String]? {
        contextCache.get(query)
    }
    
    public func setCachedContext(_ results: [String], query: String) {
        contextCache.set(query, value: results, ttl: TTL.context)
    }
    
    // MARK: - Invalidation
    
    /// Invalidate all caches (call after writes)
    public func invalidateAll() {
        profileCache.invalidateAll()
        l2NodesCache.invalidateAll()
        l2StatementsCache.invalidateAll()
        entityExpansionCache.invalidateAll()
        ftsSearchCache.invalidateAll()
        contextCache.invalidateAll()
    }
    
    /// Invalidate L2 caches (call after L2 writes)
    public func invalidateL2() {
        l2NodesCache.invalidateAll()
        l2StatementsCache.invalidateAll()
        contextCache.invalidateAll()
        ftsSearchCache.invalidateAll()
    }
    
    /// Invalidate L4 caches (call after L4 writes)
    public func invalidateL4() {
        entityExpansionCache.invalidateAll()
        contextCache.invalidateAll()
        ftsSearchCache.invalidateAll()
    }
    
    // MARK: - Statistics
    
    public var stats: CacheStats {
        CacheStats(
            profileCount: profileCache.count,
            l2NodesCount: l2NodesCache.count,
            l2StatementsCount: l2StatementsCache.count,
            entityExpansionCount: entityExpansionCache.count,
            ftsSearchCount: ftsSearchCache.count,
            contextCount: contextCache.count
        )
    }
}

public struct CacheStats {
    public let profileCount: Int
    public let l2NodesCount: Int
    public let l2StatementsCount: Int
    public let entityExpansionCount: Int
    public let ftsSearchCount: Int
    public let contextCount: Int
    
    public var totalCount: Int {
        profileCount + l2NodesCount + l2StatementsCount + entityExpansionCount + ftsSearchCount + contextCount
    }
}
