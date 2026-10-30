import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphBase
@testable import ConnorGraphAgentMac

struct MiniAppFeatureParityTests {
    @Test @MainActor func modernUsageGuideAndAllNotesAreVisible() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = try BaseLibraryStore(directory: root)
        defer { library.close(); try? FileManager.default.removeItem(at: root) }
        let package: [String: Any] = ["manifest": ["appID": "guide_test", "name": "Guide"], "schema": ["tables": []], "guide": ["authoring": ["summary": "Authoring"], "usage": ["summary": "COMPLETE_USAGE_TAIL", "notes": (0..<12).map { "note-\($0)" }]], "methods": []]
        let reviewed = try BasePackageImporter.review(JSONSerialization.data(withJSONObject: package))
        _ = try BasePackageImporter.install(reviewed, library: library)
        let model = MiniAppFeatureModel(library: library, cloudClient: nil)
        model.reload(); model.select(appID: "guide_test")
        for _ in 0..<1000 { if model.selectedDetail != nil { break }; await Task.yield() }
        #expect(model.selectedDetail?.guideSummary.contains("COMPLETE_USAGE_TAIL") == true)
        #expect(model.selectedDetail?.guideNotes.count == 12)
        #expect(model.selectedDetail?.guideNotes.last == "note-11")
    }
    @Test @MainActor func staleDetailCannotReplaceNewSelection() async throws {
        let transport = MiniAppParityTransport()
        let model = MiniAppFeatureModel(library: nil, cloudClient: .init(baseURL: URL(string: "https://example.invalid")!, transport: transport, credentials: MiniAppParityCredentials()))
        model.reload()
        for _ in 0..<1000 { if model.entries.count == 2 { break }; await Task.yield() }
        model.select(appID: "old")
        await transport.waitForOld()
        model.select(appID: "new")
        for _ in 0..<1000 { if model.selectedDetail?.appID == "new" { break }; await Task.yield() }
        #expect(model.selectedDetail?.appID == "new")
        await transport.releaseOld()
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.selectedDetail?.appID == "new")
    }
    @Test @MainActor func oldSearchPageCannotPolluteNewFilter() async throws {
        let transport = MiniAppParityTransport()
        let model = MiniAppFeatureModel(library: nil, cloudClient: .init(baseURL: URL(string: "https://example.invalid")!, transport: transport, credentials: MiniAppParityCredentials()))
        model.applySearchQuery("old-filter")
        await transport.waitForOld()
        model.applySearchQuery("new-filter")
        for _ in 0..<1000 { if model.entries.first?.appID == "filtered" { break }; await Task.yield() }
        await transport.releaseOld()
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.entries.map(\.appID) == ["filtered"])
        #expect(!model.isLoading)
    }
}
private struct MiniAppParityCredentials: CloudKnowledgeCredentialProvider {
    func accessToken() async throws -> String { "local-test-token" }
}
private actor MiniAppParityTransport: ConnorBackendHTTPTransport {
    private var pending: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func waitForOld() async { if pending != nil { return }; await withCheckedContinuation { waiter = $0 } }
    func releaseOld() { pending?.resume(); pending = nil }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let args = body["args"] as! [String: Any]
        let isList = body["tool"] as? String == "base.app.list"
        let id = args["appID"] as? String ?? ""
        let query = args["query"] as? String ?? ""
        if id == "old" || query == "old-filter" { await withCheckedContinuation { pending = $0; waiter?.resume(); waiter = nil } }
        func item(_ id: String) -> [String: Any] { ["appId": id, "name": id, "domain": "", "purpose": "", "visibility": "public", "ownerId": 1, "ownerName": "owner", "methodCount": 0, "tableCount": 0, "packageVersion": 1, "isOwner": false, "updatedAt": "2026-10-30"] }
        let data: [String: Any]
        if isList { data = ["items": query == "new-filter" ? [item("filtered")] : [item("old"), item("new")], "page": 1, "limit": 20, "total": 2, "hasMore": false] }
        else { var detail = item(id); detail["riskLevel"] = "low"; detail["sdkVersion"] = 1; detail["capabilities"] = []; detail["methods"] = []; detail["dataTableCount"] = 0; data = detail }
        return (try JSONSerialization.data(withJSONObject: ["ok": true, "data": data]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
