import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("IM API Client Tests")
struct ImAPIClientTests {
    @Test func deviceSocketFrameRouting() {
        #expect(ConnorDeviceSocketFrameRoute.classify(type: "connected") == .syncWake)
        #expect(ConnorDeviceSocketFrameRoute.classify(type: "sync_changed") == .syncWake)
        #expect(ConnorDeviceSocketFrameRoute.classify(type: "sync_peer_online") == .syncWake)
        #expect(ConnorDeviceSocketFrameRoute.classify(type: "heartbeat_ack") == .control)
        #expect(ConnorDeviceSocketFrameRoute.classify(type: "chat_receive") == .im(type: "chat_receive"))
        #expect(ConnorDeviceSocketFrameRoute.classify(type: "group_receive") == .im(type: "group_receive"))
        #expect(ConnorDeviceSocketFrameRoute.classify(type: "friend_request_received") == .im(type: "friend_request_received"))
        #expect(ConnorDeviceSocketFrameRoute.classify(type: "error") == .im(type: "error"))
        // Protocol quirk: chat_send/group_send acks are bare typeless message JSON.
        #expect(ConnorDeviceSocketFrameRoute.classify(type: nil) == .im(type: nil))
    }

    @Test func conversationsUnwrapEnvelopeAndApplyDefaults() async throws {
        let transport = StubTransport(json: """
            {"code":0,"msg":"ok","data":[
                {"peerId":42,"lastMessageContent":"你好","unreadCount":3},
                {"peerId":7}
            ]}
            """)
        let client = makeClient(transport: transport)

        let conversations = try await client.conversations(token: "t")

        #expect(conversations.count == 2)
        #expect(conversations[0].peerId == 42)
        #expect(conversations[0].lastMessageContent == "你好")
        #expect(conversations[0].unreadCount == 3)
        #expect(conversations[1].unreadCount == 0)
        #expect(conversations[1].lastMessageId == "")
        let request = try #require(transport.lastRequest)
        #expect(request.url?.absoluteString == "https://backend.example/api/v1/chat/conversations")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(request.httpMethod == "GET")
    }

    @Test func chatHistoryDecodesSnakeCaseHasMoreAndBeforeIdQuery() async throws {
        let transport = StubTransport(json: """
            {"code":0,"data":{"messages":[
                {"messageId":"m1","senderId":9,"content":"hi","status":"sent","sentAt":"2026-07-30T10:00:00Z"}
            ],"has_more":true}}
            """)
        let client = makeClient(transport: transport)

        let history = try await client.chatHistory(token: "t", peerId: 9, beforeId: "m0", limit: 20)

        #expect(history.hasMore)
        #expect(history.messages.first?.messageId == "m1")
        #expect(history.messages.first?.messageType == "text")
        #expect(history.messages.first?.extra == "{}")
        #expect(transport.lastRequest?.url?.absoluteString == "https://backend.example/api/v1/chat/history/9?limit=20&before_id=m0")
    }

    @Test func friendsDecodeUppercaseIDKey() async throws {
        let transport = StubTransport(json: """
            {"code":0,"data":[
                {"ID":11,"userId":1,"friendId":2,"username":"alice","nickname":"艾丽"}
            ]}
            """)
        let client = makeClient(transport: transport)

        let friends = try await client.friends(token: "t")

        #expect(friends.first?.id == 11)
        #expect(friends.first?.username == "alice")
        #expect(friends.first?.status == "accepted")
    }

    @Test func friendRequestsDecodeUppercaseIDKey() async throws {
        let transport = StubTransport(json: """
            {"code":0,"data":[
                {"ID":5,"senderId":1,"receiverId":2,"message":"加个好友","senderUsername":"alice","createdAt":"2026-07-30T10:00:00Z"}
            ]}
            """)
        let client = makeClient(transport: transport)

        let requests = try await client.receivedFriendRequests(token: "t")

        #expect(requests.first?.id == 5)
        #expect(requests.first?.status == "pending")
        #expect(requests.first?.message == "加个好友")
    }

    @Test func nonZeroEnvelopeCodeThrowsServerError() async throws {
        let transport = StubTransport(json: #"{"code":40001,"msg":"参数错误"}"#)
        let client = makeClient(transport: transport)

        await #expect(throws: ConnorBackendAPIError.server(status: 200, message: "参数错误")) {
            _ = try await client.conversations(token: "t")
        }
    }

    @Test func unauthorizedStatusThrowsUnauthorized() async throws {
        let transport = StubTransport(json: "{}", statusCode: 401)
        let client = makeClient(transport: transport)

        await #expect(throws: ConnorBackendAPIError.unauthorized) {
            _ = try await client.conversations(token: "expired")
        }
    }

    @Test func inviteGroupMemberSendsSnakeCaseUserId() async throws {
        let transport = StubTransport(json: #"{"code":0,"msg":"ok"}"#)
        let client = makeClient(transport: transport)

        try await client.inviteGroupMember(token: "t", groupId: "g-1", userId: 42)

        let request = try #require(transport.lastRequest)
        #expect(request.url?.absoluteString == "https://backend.example/api/v1/group-chats/g-1/members")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["user_id"] as? Int == 42)
    }

    @Test func groupMessagesDecodeWithoutStatusField() async throws {
        let transport = StubTransport(json: """
            {"code":0,"data":{"messages":[
                {"messageId":"gm1","groupId":"g-1","senderId":3,"content":"大家好","sentAt":"2026-07-30T10:00:00Z"}
            ],"has_more":false}}
            """)
        let client = makeClient(transport: transport)

        let history = try await client.groupMessages(token: "t", groupId: "g-1")

        #expect(history.messages.first?.messageId == "gm1")
        #expect(history.messages.first?.isAgent == false)
        #expect(!history.hasMore)
    }

    // MARK: - Helpers

    private func makeClient(transport: StubTransport) -> ImAPIClient {
        ImAPIClient(baseURL: URL(string: "https://backend.example")!, transport: transport)
    }
}

private final class StubTransport: ConnorBackendHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let json: String
    private let statusCode: Int
    private var _lastRequest: URLRequest?

    var lastRequest: URLRequest? {
        lock.withLock { _lastRequest }
    }

    init(json: String, statusCode: Int = 200) {
        self.json = json
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { _lastRequest = request }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(json.utf8), response)
    }
}
