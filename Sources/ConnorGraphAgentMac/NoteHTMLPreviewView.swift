import SwiftUI
import WebKit
import ConnorGraphAppSupport

/// HTML 笔记正文的安全只读预览：WKWebView + 禁用 JavaScript + 净化后的文档。
///
/// 仅在查看 HTML 格式笔记正文时实例化（单个 WebView），聊天气泡的普通
/// Markdown 仍走既有编译渲染，避免每个气泡一个 WebView 的性能开销。
struct NoteHTMLPreviewView: View {
    let html: String

    @State private var intrinsicHeight: CGFloat = 320

    var body: some View {
        Representable(
            document: NoteHTMLSanitizer.document(html: html),
            intrinsicHeight: $intrinsicHeight
        )
        .frame(height: intrinsicHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private struct Representable: NSViewRepresentable {
        let document: String
        @Binding var intrinsicHeight: CGFloat

        func makeCoordinator() -> Coordinator { Coordinator(document: document, intrinsicHeight: $intrinsicHeight) }

        func makeNSView(context: Context) -> WKWebView {
            let webView = WKWebView(frame: .zero, configuration: MailWebViewConfigurationProvider.shared.makeConfiguration())
            webView.navigationDelegate = context.coordinator
            webView.setValue(false, forKey: "drawsBackground")
            context.coordinator.load(document, in: webView)
            return webView
        }

        func updateNSView(_ webView: WKWebView, context: Context) {
            context.coordinator.load(document, in: webView)
        }

        @MainActor
        final class Coordinator: NSObject, WKNavigationDelegate {
            private let document: String
            private var intrinsicHeight: Binding<CGFloat>
            private var lastLoadedDocument: String?
            private var remainingHeightProbes = 3

            init(document: String, intrinsicHeight: Binding<CGFloat>) {
                self.document = document
                self.intrinsicHeight = intrinsicHeight
            }

            func load(_ document: String, in webView: WKWebView) {
                guard document != lastLoadedDocument else { return }
                lastLoadedDocument = document
                webView.loadHTMLString(document, baseURL: nil)
            }

            func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
                remainingHeightProbes = 3
                probeContentHeight(of: webView)
            }

            func webView(
                _ webView: WKWebView,
                decidePolicyFor navigationAction: WKNavigationAction,
                decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
            ) {
                // 只读预览：允许初始 loadHTMLString，其余导航一律拦截（链接/表单等）。
                if navigationAction.targetFrame?.isMainFrame == true,
                   navigationAction.navigationType == .other {
                    decisionHandler(.allow)
                } else {
                    decisionHandler(.cancel)
                }
            }

            private func probeContentHeight(of webView: WKWebView) {
                webView.evaluateJavaScript("document.body.scrollHeight") { [weak self, weak webView] result, _ in
                    guard let self, let webView, let height = result as? NSNumber else { return }
                    let proposed = CGFloat(height.doubleValue)
                    if proposed > 0, abs(proposed - self.intrinsicHeight.wrappedValue) > 1 {
                        self.intrinsicHeight.wrappedValue = proposed
                    }
                    // 图片等异步加载会撑开内容，做少量延迟校准后停止，避免无限探测。
                    if self.remainingHeightProbes > 0 {
                        self.remainingHeightProbes -= 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak webView] in
                            guard let self, let webView else { return }
                            self.probeContentHeight(of: webView)
                        }
                    }
                }
            }
        }
    }
}
