import SwiftUI
import AppKit
import WebKit
import ConnorGraphCore
import ConnorGraphAppSupport

struct EmbeddedWebView: NSViewRepresentable {
    var webView: WKWebView
    var initialURLString: String
    var onWebViewCreated: (WKWebView) -> Void

    func makeNSView(context: Context) -> BrowserWebViewContainerView {
        let container = BrowserWebViewContainerView()
        container.attach(webView)
        onWebViewCreated(webView)
        return container
    }

    func updateNSView(_ nsView: BrowserWebViewContainerView, context: Context) {
        nsView.attach(webView)
        onWebViewCreated(webView)
    }

    static let selectionObserverScript = """
    (function() {
      if (window.__connorSelectionObserverInstalled) { return; }
      window.__connorSelectionObserverInstalled = true;

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

      var lastKey = '';
      var timer = null;
      function reportSelection() {
        clearTimeout(timer);
        timer = setTimeout(function() {
          try {
            var selection = window.getSelection ? window.getSelection() : null;
            var text = selection ? selection.toString().trim() : '';
            if (!selection || !text || selection.rangeCount === 0) { return; }
            var rect = selection.getRangeAt(0).getBoundingClientRect();
            if (!rect || (rect.width === 0 && rect.height === 0)) { return; }
            var key = text + '|' + location.href + '|' + Math.round(rect.x) + '|' + Math.round(rect.y);
            if (key === lastKey) { return; }
            lastKey = key;
            window.webkit.messageHandlers.connorSelection.postMessage(JSON.stringify({
              pageURL: location.href || '',
              pageTitle: document.title || '',
              pageText: readablePageText(),
              selectedText: text,
              rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
            }));
          } catch (error) {}
        }, 80);
      }

      document.addEventListener('selectionchange', reportSelection, true);
      document.addEventListener('mouseup', reportSelection, true);
      document.addEventListener('keyup', reportSelection, true);
    })();
    """

}

extension WKWebView {
    func loadBrowserURLString(_ urlString: String) {
        if urlString == BrowserBuiltInPage.blankURLString || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            loadHTMLString(BrowserBuiltInPage.blankHTML, baseURL: BrowserBuiltInPage.webViewBaseURL)
            return
        }
        guard let url = URL(string: urlString) else {
            loadHTMLString(BrowserBuiltInPage.errorHTML(failedURLString: urlString, message: "Invalid URL"), baseURL: BrowserBuiltInPage.webViewBaseURL)
            return
        }
        load(URLRequest(url: url))
    }

    func pauseBrowserMediaPlayback() {
        if #available(macOS 12.0, *) {
            pauseAllMediaPlayback { }
        }
    }
}

extension UUID {
    static func nameUUIDFromBytes(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "00000000-0000-4000-8000-%012llx", hash & 0x0000_FFFF_FFFF_FFFF)
    }
}
