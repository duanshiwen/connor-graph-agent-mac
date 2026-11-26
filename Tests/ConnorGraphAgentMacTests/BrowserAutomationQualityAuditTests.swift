import Foundation
import Testing
import WebKit
@testable import ConnorGraphAgentMac
import ConnorGraphAgent
import ConnorGraphAppSupport

@MainActor
@Suite("Browser Automation Quality Audit Tests")
struct BrowserAutomationQualityAuditTests {
    @Test func auditsRenderedMobilePageAndReturnsVisualEvidence() async throws {
        let sessionID = "quality-audit-session"
        let tab = AppBrowserTabSnapshot(
            initialURLString: BrowserBuiltInPage.blankURLString,
            currentURLString: BrowserBuiltInPage.blankURLString
        )
        var snapshot = AppBrowserStateSnapshot(tabs: [tab], selectedTabID: tab.id)
        let store = BrowserLiveWebViewStore()
        let runtime = BrowserAutomationRuntime(
            liveStore: store,
            snapshotProvider: { requestedSessionID in
                requestedSessionID == sessionID ? snapshot : nil
            },
            snapshotSaver: { updated, requestedSessionID in
                if requestedSessionID == sessionID { snapshot = updated }
            },
            showWorkspace: { _ in }
        )
        defer { runtime.shutdown() }

        let webView = runtime.ensureWebView(
            sessionID: sessionID,
            tabID: tab.id,
            initialURLString: BrowserBuiltInPage.blankURLString
        ).webView
        webView.loadHTMLString(
            """
            <!doctype html>
            <html lang="en">
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>Quality audit fixture</title>
              <script>console.error('fixture runtime failure')</script>
            </head>
            <body>
              <main>
                <h1>Fixture</h1>
                <div style="width: 640px">This content deliberately overflows.</div>
                <img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=">
                <button></button>
              </main>
            </body>
            </html>
            """,
            baseURL: URL(string: "http://localhost/fixture")
        )
        try await waitUntilLoaded(webView)

        let response = try await runtime.perform(BrowserControlRequest(
            operation: .qualityAudit,
            sessionID: sessionID,
            tabID: tab.id.uuidString,
            fullPage: false,
            viewportWidth: 390,
            viewportHeight: 844
        ))

        let json = try #require(response.contentJSON?.data(using: .utf8))
        let report = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let viewport = try #require(report["viewport"] as? [String: Any])
        #expect((viewport["width"] as? Int) == 390)
        #expect((viewport["height"] as? Int) == 844)
        let issues = try #require(report["issues"] as? [[String: Any]])
        let issueCodes = Set(issues.compactMap { $0["code"] as? String })
        #expect(issueCodes.contains("horizontal-overflow"))
        #expect(issueCodes.contains("missing-image-alt"))
        #expect(issueCodes.contains("unnamed-control"))
        let runtimeErrors = try #require(report["runtimeErrors"] as? [[String: Any]])
        #expect(runtimeErrors.contains { ($0["message"] as? String)?.contains("fixture runtime failure") == true })
        let image = try #require(response.modelContentParts?.first)
        #expect(image.kind == .imageDataURL)
        #expect(image.dataURL?.hasPrefix("data:image/png;base64,") == true)
    }

    @Test func collaborationVerifiesFieldsAndRequiresFreshObservationAfterTakeover() async throws {
        let session = "collaboration"
        let tab = AppBrowserTabSnapshot(initialURLString:BrowserBuiltInPage.blankURLString,currentURLString:BrowserBuiltInPage.blankURLString)
        var state = AppBrowserStateSnapshot(tabs:[tab],selectedTabID:tab.id)
        let runtime = BrowserAutomationRuntime(liveStore:BrowserLiveWebViewStore(),snapshotProvider:{ $0 == session ? state : nil },snapshotSaver:{ updated,_ in state=updated },showWorkspace:{ _ in })
        defer { runtime.shutdown() }
        let view = runtime.ensureWebView(sessionID:session,tabID:tab.id,initialURLString:BrowserBuiltInPage.blankURLString).webView
        view.frame = CGRect(x:0,y:0,width:900,height:700)
        view.loadHTMLString("<title>Quality audit fixture</title><h1>Collaboration</h1><input aria-label='Name' id='name'><input aria-label='Revert' oninput=\"this.value=''\"><input type='password' value='SECRET_FIXTURE'><button type='submit'>Submit</button>",baseURL:URL(string:"http://localhost/collaboration"))
        try await waitUntilLoaded(view)
        func request(_ operation:BrowserControlOperation,_ action:String?=nil,_ ref:String?=nil,_ value:String?=nil)->BrowserControlRequest { BrowserControlRequest(operation:operation,sessionID:session,tabID:tab.id.uuidString,action:action,nodeReference:ref,value:value) }
        func snapshot() async throws -> [[String:Any]] {
            let response = try await runtime.perform(request(.snapshot))
            let data = try #require(response.contentJSON?.data(using:.utf8))
            let object = try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
            #expect(!String(decoding:data,as:UTF8.self).contains("SECRET_FIXTURE"))
            return try #require(object["nodes"] as? [[String:Any]])
        }
        func rejects(_ request:BrowserControlRequest) async -> Bool { do { _ = try await runtime.perform(request);return false } catch { return true } }
        var nodes = try await snapshot()
        let field = try #require(nodes.first { $0["name"] as? String == "Name" }?["nodeRef"] as? String)
        let filled = try await runtime.perform(request(.interact,"fill",field,"draft"))
        #expect(filled.contentJSON?.contains("verified") == true)
        _ = try await runtime.perform(request(.verifyResult,"value",field,"draft"))
        _ = try await view.callAsyncJavaScript("document.querySelector('#name').value='user edit';return true",arguments:[:],in:nil,contentWorld:.page)
        #expect(await rejects(request(.interact,"fill",field,"overwrite")))
        nodes = try await snapshot()
        let newField = try #require(nodes.first { $0["name"] as? String == "Name" }?["nodeRef"] as? String)
        #expect(field != newField)
        #expect(await rejects(request(.interact,"fill",field,"stale")))
        let revert = try #require(nodes.first { $0["name"] as? String == "Revert" }?["nodeRef"] as? String)
        #expect(await rejects(request(.interact,"fill",revert,"rejected")))
        let submit = try #require(nodes.first { $0["name"] as? String == "Submit" }?["nodeRef"] as? String)
        #expect(await rejects(request(.interact,"click",submit)))
        runtime.pause(session,reason:"human takeover")
        #expect(runtime.isPaused(session))
        #expect(!runtime.isPaused("another-session"))
        #expect(await rejects(request(.interact,"fill",newField,"blocked")))
        _ = try await runtime.perform(request(.readPage,nil,nil,"page"))
        await runtime.resume(session)
        #expect(!runtime.isPaused(session))
        #expect(await rejects(request(.interact,"fill",newField,"stale")))
        _ = try await runtime.perform(request(.handoff,nil,nil,"manual verification"))
        #expect(runtime.isPaused(session))
    }

    private func waitUntilLoaded(_ webView: WKWebView) async throws {
        for _ in 0..<100 {
            if !webView.isLoading,
               let title = try? await webView.callAsyncJavaScript(
                   "return document.title;",
                   arguments: [:],
                   in: nil,
                   contentWorld: .page
               ) as? String,
               title == "Quality audit fixture" {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out loading the quality audit fixture")
    }
}
