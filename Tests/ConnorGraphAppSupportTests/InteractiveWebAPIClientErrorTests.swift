import Foundation
import Testing
import CryptoKit
import ConnorGraphAppSupport

private struct InteractiveWebTestCredential: CloudKnowledgeCredentialProvider {
    func accessToken() async throws -> String { "test-token" }
}

private struct StubInteractiveWebTransport: ConnorBackendHTTPTransport, @unchecked Sendable {
    var statusCode: Int
    var body: Data

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

private actor SequencedInteractiveWebTransport: ConnorBackendHTTPTransport {
    private let responses: [(Int, Data)]
    private var callCount = 0

    init(_ responses: [(Int, Data)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let index = min(callCount, responses.count - 1)
        callCount += 1
        let (statusCode, body) = responses[index]
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

@Suite("Interactive Web API Client Error Tests")
struct InteractiveWebAPIClientErrorTests {
    @Test func nonSuccessResponseCarriesBackendMessageAndStatus() async throws {
        let client = InteractiveWebAPIClient(
            baseURL: URL(string: "https://connor.example")!,
            transport: StubInteractiveWebTransport(
                statusCode: 500,
                body: Data(#"{"code":"interactive_web_error","msg":"互动网页操作失败"}"#.utf8)
            ),
            credentials: InteractiveWebTestCredential()
        )

        do {
            _ = try await client.projects()
            Issue.record("Expected the publish API to throw for a non-2xx response")
        } catch let error as InteractiveWebAPIError {
            guard case .server(let statusCode, let message) = error else {
                Issue.record("Expected .server, got \(error)")
                return
            }
            #expect(statusCode == 500)
            #expect(message == "互动网页操作失败")
            #expect(error.errorDescription == "互动网页操作失败")
            #expect(String(describing: error).contains("互动网页操作失败"))
        }
    }

    @Test func nonJSONErrorBodyFallsBackToHTTPStatus() async throws {
        let client = InteractiveWebAPIClient(
            baseURL: URL(string: "https://connor.example")!,
            transport: StubInteractiveWebTransport(
                statusCode: 502,
                body: Data("Bad Gateway".utf8)
            ),
            credentials: InteractiveWebTestCredential()
        )

        do {
            _ = try await client.projects()
            Issue.record("Expected the publish API to throw for a non-2xx response")
        } catch let error as InteractiveWebAPIError {
            guard case .server(let statusCode, let message) = error else {
                Issue.record("Expected .server, got \(error)")
                return
            }
            #expect(statusCode == 502)
            #expect(message.isEmpty)
            #expect(error.errorDescription == "服务器错误（HTTP 502）")
            #expect(!String(describing: error).contains("server"))
        }
    }

    @Test func uploadFailureSurfacesBackendMessage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("interactive-web-upload-error-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let html = "<html><body>Hello</body></html>"
        try Data(html.utf8).write(to: root.appendingPathComponent("index.html"))
        let digest = SHA256.hash(data: Data(html.utf8)).map { String(format: "%02x", $0) }.joined()
        let project = LocalInteractiveWebProject(
            accountID: "account-1",
            name: "Upload Error",
            rootURL: root,
            conversationID: "session-1"
        )
        let manifest = InteractiveWebManifest(files: [
            InteractiveWebManifestFile(path: "index.html", sha256: digest, mediaType: "text/html", sizeBytes: Int64(html.utf8.count))
        ])
        let uploadURL = "https://connor.example/api/v1/deployments/d1/files/index.html?expires=1&signature=x"
        let transport = SequencedInteractiveWebTransport([
            (200, Data(#"{"data":{"id":"p1","siteId":"s1"}}"#.utf8)),
            (200, Data(#"{"data":{"id":"d1"}}"#.utf8)),
            (200, Data(#"{"data":{"uploadUrls":{"index.html":"\#(uploadURL)"}}}"#.utf8)),
            (500, Data(#"{"code":"upload_rejected","msg":"文件校验失败"}"#.utf8))
        ])
        let client = InteractiveWebAPIClient(
            baseURL: URL(string: "https://connor.example")!,
            transport: transport,
            credentials: InteractiveWebTestCredential()
        )

        do {
            _ = try await client.publish(project: project, manifest: manifest)
            Issue.record("Expected the upload step to fail")
        } catch let error as InteractiveWebAPIError {
            guard case .uploadFailed(let statusCode, let message) = error else {
                Issue.record("Expected .uploadFailed, got \(error)")
                return
            }
            #expect(statusCode == 500)
            #expect(message == "文件校验失败")
            #expect(error.errorDescription == "互动网页文件上传失败：文件校验失败")
        }
    }
}
