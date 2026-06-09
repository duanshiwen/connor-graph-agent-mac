import SwiftUI
import WebKit
import ConnorGraphAppSupport

struct BrowserWorkspaceView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var addressText: String = "https://www.wikipedia.org"
    @State private var webView: WKWebView?
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var pageTitle = ""
    @State private var pageURL = ""
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
                        self.webView = webView
                    },
                    onNavigationStateChanged: { state in
                        canGoBack = state.canGoBack
                        canGoForward = state.canGoForward
                        pageTitle = state.title
                        pageURL = state.url
                        if !state.url.isEmpty { addressText = state.url }
                    },
                    onSelectionChanged: { context in
                        selectionContext = context
                        showSelectionComposer = context.hasSelectionContext
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
            if let current = URL(string: addressText), webView?.url == nil {
                webView?.load(URLRequest(url: current))
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
        webView?.load(URLRequest(url: url))
    }
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

private struct WebNavigationState: Equatable {
    var canGoBack: Bool
    var canGoForward: Bool
    var title: String
    var url: String
}

private struct EmbeddedWebView: NSViewRepresentable {
    var initialURLString: String
    var onWebViewCreated: (WKWebView) -> Void
    var onNavigationStateChanged: (WebNavigationState) -> Void
    var onSelectionChanged: (BrowserSelectionContext) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onNavigationStateChanged: onNavigationStateChanged,
            onSelectionChanged: onSelectionChanged
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "selectionBridge")
        userContentController.addUserScript(WKUserScript(source: Self.selectionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        configuration.userContentController = userContentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        onWebViewCreated(webView)

        if let url = URL(string: initialURLString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static let selectionScript = """
    (function() {
      if (window.__connorSelectionBridgeInstalled) { return; }
      window.__connorSelectionBridgeInstalled = true;

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
        return text.replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim().slice(0, 60000);
      }

      function sendSelection(payload) {
        payload.pageURL = location.href || '';
        payload.pageTitle = document.title || '';
        payload.pageText = readablePageText();
        window.webkit.messageHandlers.selectionBridge.postMessage(payload);
      }

      document.addEventListener('mouseup', function() {
        setTimeout(function() {
          var selection = window.getSelection ? window.getSelection().toString() : '';
          if (selection && selection.trim().length > 0) {
            sendSelection({ selectedText: selection.trim() });
          }
        }, 50);
      }, true);

      document.addEventListener('click', function(event) {
        var target = event.target;
        if (target && target.tagName && target.tagName.toLowerCase() === 'img') {
          sendSelection({
            selectedText: '',
            imageURL: absoluteURL(target.currentSrc || target.src),
            imageAlt: target.alt || target.title || ''
          });
        }
      }, true);
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var onNavigationStateChanged: (WebNavigationState) -> Void
        var onSelectionChanged: (BrowserSelectionContext) -> Void

        init(
            onNavigationStateChanged: @escaping (WebNavigationState) -> Void,
            onSelectionChanged: @escaping (BrowserSelectionContext) -> Void
        ) {
            self.onNavigationStateChanged = onNavigationStateChanged
            self.onSelectionChanged = onSelectionChanged
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

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "selectionBridge", let body = message.body as? [String: Any] else { return }
            let page = BrowserPageContext(
                url: body["pageURL"] as? String ?? webView?.url?.absoluteString ?? "",
                title: body["pageTitle"] as? String ?? webView?.title ?? "",
                text: body["pageText"] as? String ?? ""
            )
            let imageURL = body["imageURL"] as? String
            let image = imageURL.map { BrowserSelectedImageContext(url: $0, alt: body["imageAlt"] as? String) }
            let context = BrowserSelectionContext(
                page: page,
                selectedText: body["selectedText"] as? String ?? "",
                image: image
            )
            guard context.hasSelectionContext else { return }
            DispatchQueue.main.async { self.onSelectionChanged(context) }
        }

        private func publishNavigationState(_ webView: WKWebView) {
            let state = WebNavigationState(
                canGoBack: webView.canGoBack,
                canGoForward: webView.canGoForward,
                title: webView.title ?? "",
                url: webView.url?.absoluteString ?? ""
            )
            DispatchQueue.main.async { self.onNavigationStateChanged(state) }
        }
    }
}
