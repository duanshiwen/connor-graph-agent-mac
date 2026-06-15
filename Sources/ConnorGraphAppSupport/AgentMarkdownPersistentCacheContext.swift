import Foundation

public struct AgentMarkdownPersistentCacheContext: Sendable {
    public var store: AgentMarkdownRenderCacheStore
    public var sessionID: String
    public var messageID: String

    public init(store: AgentMarkdownRenderCacheStore, sessionID: String, messageID: String) {
        self.store = store
        self.sessionID = sessionID
        self.messageID = messageID
    }
}
