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
