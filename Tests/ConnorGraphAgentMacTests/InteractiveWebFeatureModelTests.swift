import Foundation
import Testing
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

struct InteractiveWebFeatureModelTests {
    @Test @MainActor func delayedDetailCannotReplaceNewSelection() async throws {
        let transport = InteractiveWebFeatureTransport()
        let model = InteractiveWebFeatureModel(client: .init(baseURL: URL(string: "https://example.invalid")!, transport: transport, credentials: InteractiveWebFeatureCredentials()))
        model.select(try project("old"))
        await transport.waitForOldRequest()
        model.select(try project("new"))
        for _ in 0..<1000 { if model.detail?.id == "new" { break }; await Task.yield() }
        #expect(model.detail?.id == "new")
        await transport.releaseOld()
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.selectedProjectID == "new")
        #expect(model.detail?.id == "new")
    }

    @Test @MainActor func clearingSelectionRejectsInFlightDetail() async throws {
        let transport = InteractiveWebFeatureTransport()
        let model = InteractiveWebFeatureModel(client: .init(baseURL: URL(string: "https://example.invalid")!, transport: transport, credentials: InteractiveWebFeatureCredentials()))
        model.select(try project("old"))
        await transport.waitForOldRequest()
        model.clearSelection()
        await transport.releaseOld()
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.selectedProjectID == nil)
        #expect(model.detail == nil)
    }

    @Test @MainActor func loadsProjectsBeyondFirstHundred() async throws {
        let transport = InteractiveWebFeatureTransport()
        let model = InteractiveWebFeatureModel(client: .init(baseURL: URL(string: "https://example.invalid")!, transport: transport, credentials: InteractiveWebFeatureCredentials()))
        await model.reloadProjects()
        #expect(model.projects.count == 100)
        #expect(model.hasMoreProjects)
        await model.loadMoreProjects()
        #expect(model.projects.count == 101)
        #expect(model.projects.last?.id == "100")
        #expect(!model.hasMoreProjects)
    }

    private func project(_ id: String) throws -> InteractiveWebRemoteProject {
        try JSONDecoder().decode(InteractiveWebRemoteProject.self, from: JSONSerialization.data(withJSONObject: projectObject(id)))
    }
}

private struct InteractiveWebFeatureCredentials: CloudKnowledgeCredentialProvider {
    func accessToken() async throws -> String { "local-test-token" }
}

private func projectObject(_ id: String) -> [String: Any] {
    ["id": id, "name": id, "siteId": "site-" + id, "status": "active", "accessMode": "private", "createdAt": "2026-10-30T00:00:00Z", "updatedAt": "2026-10-30T00:00:00Z"]
}

private actor InteractiveWebFeatureTransport: ConnorBackendHTTPTransport {
    private var pendingOld: CheckedContinuation<Void, Never>?
    private var oldRequestWaiter: CheckedContinuation<Void, Never>?
    func waitForOldRequest() async {
        if pendingOld != nil { return }
        await withCheckedContinuation { oldRequestWaiter = $0 }
    }
    func releaseOld() { pendingOld?.resume(); pendingOld = nil }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        if url.lastPathComponent == "old" {
            await withCheckedContinuation { continuation in
                pendingOld = continuation
                oldRequestWaiter?.resume(); oldRequestWaiter = nil
            }
        }
        let object: Any
        if url.lastPathComponent == "projects" {
            let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value
            object = (page == "2" ? [100] : Array(0..<100)).map { projectObject(String($0)) }
        } else {
            var detail = projectObject(url.lastPathComponent)
            detail["deployments"] = []; detail["files"] = []; detail["collections"] = []
            object = detail
        }
        return (try JSONSerialization.data(withJSONObject: ["code": 0, "data": object]), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
