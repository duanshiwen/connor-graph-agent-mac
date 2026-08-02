import Foundation
import WebKit

@MainActor
final class InteractiveWebPreviewRuntime: NSObject, WKNavigationDelegate {
    nonisolated static let scheme = "connor-preview"
    nonisolated static let contentSecurityPolicy = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'none'; frame-ancestors 'none';"

    private let projectRoot: URL
    private let schemeHandler: SchemeHandler
    let webView: WKWebView

    init(projectRoot: URL) {
        self.projectRoot = projectRoot.resolvingSymlinksInPath().standardizedFileURL
        let schemeHandler = SchemeHandler()
        self.schemeHandler = schemeHandler
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: Self.scheme)
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        schemeHandler.target = self
        webView.navigationDelegate = self
    }

    func load() {
        webView.load(URLRequest(url: URL(string: "\(Self.scheme)://project/index.html")!))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.scheme == Self.scheme ? .allow : .cancel)
    }

    private func serve(_ task: any WKURLSchemeTask) {
        guard let url = task.request.url, url.scheme == Self.scheme, url.host == "project" else { fail(task); return }
        let relative = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let file = projectRoot.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(projectRoot.path + "/"), let data = try? Data(contentsOf: file) else { fail(task); return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": Self.mediaType(file.pathExtension), "Content-Security-Policy": Self.contentSecurityPolicy,
            "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer", "Cache-Control": "no-store"
        ])!
        task.didReceive(response); task.didReceive(data); task.didFinish()
    }

    private func fail(_ task: any WKURLSchemeTask) { task.didFailWithError(URLError(.fileDoesNotExist)) }
    private static func mediaType(_ ext: String) -> String { ["html":"text/html", "css":"text/css", "js":"text/javascript", "json":"application/json", "png":"image/png", "jpg":"image/jpeg", "jpeg":"image/jpeg", "gif":"image/gif", "webp":"image/webp", "svg":"image/svg+xml", "woff":"font/woff", "woff2":"font/woff2"][ext.lowercased()] ?? "application/octet-stream" }

    private final class SchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
        weak var target: InteractiveWebPreviewRuntime?
        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) { Task { @MainActor [weak self] in self?.target?.serve(urlSchemeTask) } }
        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
    }
}
