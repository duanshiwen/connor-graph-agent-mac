import SwiftUI
import WebKit
import ConnorGraphAppSupport

struct BrowserWorkspaceView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var addressText: String = ""
    @State private var webView: WKWebView?
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var pageTitle = ""
    @State private var pageURL = ""
    @State private var isLoadingPage = false
    @State private var navigationErrorMessage: String?
    @State private var selectionContext: BrowserSelectionContext?
    @State private var selectionQuestion = ""
    @State private var showSelectionComposer = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ZStack(alignment: .bottomTrailing) {
                EmbeddedWebView(
                    initialURLString: addressText,
                    onWebViewCreated: { webView in
                        DispatchQueue.main.async {
                            self.webView = webView
                            navigate(to: viewModel.browserTargetURLString)
                        }
                    },
                    onNavigationStateChanged: { state in
                        canGoBack = state.canGoBack
                        canGoForward = state.canGoForward
                        pageTitle = state.title
                        pageURL = state.url
                        isLoadingPage = state.isLoading
                        navigationErrorMessage = state.errorMessage
                        if !state.url.isEmpty { addressText = state.url }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isLoadingPage && navigationErrorMessage == nil {
                    BrowserLoadingOverlay(message: "加载中…")
                        .padding(24)
                }

                if let navigationErrorMessage {
                    BrowserLoadingOverlay(message: navigationErrorMessage, systemImage: "exclamationmark.triangle")
                        .padding(24)
                }

                if showSelectionComposer, let selectionContext {
                    BrowserSelectionComposer(
                        context: selectionContext,
                        question: $selectionQuestion,
                        isSubmitting: viewModel.isSubmittingChat,
                        onAsk: {
                            let question = selectionQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !question.isEmpty else { return }
                            let prompt = BrowserLLMContextBuilder().makePrompt(selection: selectionContext, question: question)
                            selectionQuestion = ""
                            showSelectionComposer = false
                            Task { await viewModel.submitChat(prompt: prompt) }
                        },
                        onInsert: {
                            viewModel.chatInput = [viewModel.chatInput, BrowserLLMContextBuilder().makeContextMarkdown(selection: selectionContext)]
                                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                                .joined(separator: "\n\n")
                            showSelectionComposer = false
                        },
                        onSaveEvidence: {
                            Task { await viewModel.saveBrowserSelectionAsEpisode(selectionContext) }
                            showSelectionComposer = false
                        },
                        onClose: {
                            showSelectionComposer = false
                        }
                    )
                    .padding(18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                if addressText.isEmpty {
                    addressText = viewModel.browserTargetURLString
                }
                navigate(to: viewModel.browserTargetURLString)
            }
        }
        .onChange(of: viewModel.browserTargetURLString) { _, newValue in
            DispatchQueue.main.async {
                navigate(to: newValue)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: { webView?.goBack() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(!canGoBack)
            .help("后退")

            Button(action: { webView?.goForward() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(!canGoForward)
            .help("前进")

            Button(action: { webView?.reload() }) {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新")

            Button(action: captureSelectionFromPage) {
                Label("使用选择", systemImage: "selection.pin.in.out")
            }
            .disabled(webView == nil)
            .help("读取当前网页选中的文本或图片，避免 WebKit 通过 XPC 自动传递复杂对象")

            TextField("输入网址或搜索词", text: $addressText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { navigateFromAddressBar() }

            Button("打开") { navigateFromAddressBar() }
                .buttonStyle(.borderedProminent)

            Button(action: { viewModel.isBrowserVisible = false }) {
                Label("返回对话", systemImage: "bubble.left.and.bubble.right")
            }
            .help("关闭网页工作区，返回对话时间线")
        }
    }

    private func navigateFromAddressBar() {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let urlString: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            urlString = trimmed
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            urlString = "https://\(trimmed)"
        } else {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            urlString = "https://duckduckgo.com/?q=\(encoded)"
        }
        guard let url = URL(string: urlString) else { return }
        viewModel.browserTargetURLString = url.absoluteString
        navigate(to: url.absoluteString)
    }

    private func navigate(to urlString: String) {
        guard let url = URL(string: urlString), !urlString.isEmpty else { return }
        addressText = url.absoluteString
        guard webView?.url?.absoluteString != url.absoluteString else { return }
        webView?.load(URLRequest(url: url))
    }

    private func captureSelectionFromPage() {
        webView?.evaluateJavaScript(EmbeddedWebView.selectionCaptureScript) { result, error in
            guard error == nil, let json = result as? String, let data = json.data(using: .utf8) else { return }
            guard let payload = try? JSONDecoder().decode(BrowserSelectionPayload.self, from: data) else { return }
            let page = BrowserPageContext(
                url: payload.pageURL.isEmpty ? pageURL : payload.pageURL,
                title: payload.pageTitle.isEmpty ? pageTitle : payload.pageTitle,
                text: payload.pageText
            )
            let image = payload.imageURL.map { BrowserSelectedImageContext(url: $0, alt: payload.imageAlt) }
            let context = BrowserSelectionContext(
                page: page,
                selectedText: payload.selectedText,
                image: image
            )
            guard context.hasSelectionContext else { return }
            selectionContext = context
            showSelectionComposer = true
        }
    }
}

private struct BrowserSelectionPayload: Decodable {
    var pageURL: String
    var pageTitle: String
    var pageText: String
    var selectedText: String
    var imageURL: String?
    var imageAlt: String?
}

private struct BrowserSelectionComposer: View {
    var context: BrowserSelectionContext
    @Binding var question: String
    var isSubmitting: Bool
    var onAsk: () -> Void
    var onInsert: () -> Void
    var onSaveEvidence: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(context.image == nil ? "已选择网页文本" : "已选择网页图片", systemImage: context.image == nil ? "selection.pin.in.out" : "photo")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }

            Text(previewText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)

            TextField("对选中的内容提问…", text: $question, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit(onAsk)

            HStack {
                Button("插入到输入框", action: onInsert)
                Button("保存为证据", action: onSaveEvidence)
                Spacer()
                Button("发送给 LLM", action: onAsk)
                    .buttonStyle(.borderedProminent)
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(14)
        .frame(width: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.30), lineWidth: 1)
        )
        .shadow(radius: 18, y: 8)
    }

    private var previewText: String {
        if let image = context.image {
            return "图片：\(image.url)\(image.alt.map { "\nAlt：\($0)" } ?? "")"
        }
        let selected = context.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty { return selected }
        return context.page.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct BrowserLoadingOverlay: View {
    var message: String
    var systemImage: String = "arrow.triangle.2.circlepath"

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 1))
    }
}

private struct WebNavigationState: Equatable {
    var canGoBack: Bool
    var canGoForward: Bool
    var title: String
    var url: String
    var isLoading: Bool = false
    var errorMessage: String? = nil
}

private struct EmbeddedWebView: NSViewRepresentable {
    var initialURLString: String
    var onWebViewCreated: (WKWebView) -> Void
    var onNavigationStateChanged: (WebNavigationState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationStateChanged: onNavigationStateChanged)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        onWebViewCreated(webView)

        if let url = URL(string: initialURLString), !initialURLString.isEmpty {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static let selectionCaptureScript = """
    (function() {
      function absoluteURL(value) {
        try { return value ? new URL(value, document.baseURI).href : null; } catch (e) { return value || null; }
      }

      function readablePageText() {
        var candidates = [];
        var article = document.querySelector('article');
        if (article && article.innerText) { candidates.push(article.innerText); }
        var main = document.querySelector('main');
        if (main && main.innerText) { candidates.push(main.innerText); }
        if (document.body && document.body.innerText) { candidates.push(document.body.innerText); }
        var text = candidates.find(function(value) { return value && value.trim().length > 0; }) || '';
        return text.replace(/[ \\t]+/g, ' ').replace(/\\n{3,}/g, '\\n\\n').trim().slice(0, 60000);
      }

      var selection = window.getSelection ? window.getSelection().toString() : '';
      var active = document.activeElement;
      var imageURL = null;
      var imageAlt = null;
      if (active && active.tagName && active.tagName.toLowerCase() === 'img') {
        imageURL = absoluteURL(active.currentSrc || active.src);
        imageAlt = active.alt || active.title || '';
      }

      return JSON.stringify({
        pageURL: location.href || '',
        pageTitle: document.title || '',
        pageText: readablePageText(),
        selectedText: (selection || '').trim(),
        imageURL: imageURL,
        imageAlt: imageAlt
      });
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        var onNavigationStateChanged: (WebNavigationState) -> Void

        init(onNavigationStateChanged: @escaping (WebNavigationState) -> Void) {
            self.onNavigationStateChanged = onNavigationStateChanged
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            publishNavigationState(webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            publishNavigationState(webView)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            publishNavigationState(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            publishNavigationState(webView, errorMessage: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            publishNavigationState(webView, errorMessage: error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        private func publishNavigationState(_ webView: WKWebView, errorMessage: String? = nil) {
            let state = WebNavigationState(
                canGoBack: webView.canGoBack,
                canGoForward: webView.canGoForward,
                title: webView.title ?? "",
                url: webView.url?.absoluteString ?? "",
                isLoading: webView.isLoading,
                errorMessage: errorMessage
            )
            DispatchQueue.main.async { self.onNavigationStateChanged(state) }
        }
    }
}
