import Foundation

struct ChatViewportDataSetID: Hashable, Sendable, CustomStringConvertible {
    var namespace: String
    var rawID: String
    var revision: Int

    init(namespace: String, rawID: String, revision: Int = 0) {
        self.namespace = namespace
        self.rawID = rawID
        self.revision = revision
    }

    var description: String {
        "\(namespace):\(rawID):\(revision)"
    }

    func namespacedElementID(_ elementID: String) -> String {
        "\(description)::\(elementID)"
    }
}

extension ChatViewportDataSetID {
    static func agentChatSession(sessionID: String?, revision: Int) -> ChatViewportDataSetID {
        ChatViewportDataSetID(
            namespace: "agent-chat-session",
            rawID: sessionID ?? "none",
            revision: revision
        )
    }
}
