import SwiftUI
import AppKit
import WebKit
import ConnorGraphCore
import ConnorGraphAppSupport

enum BrowserMediaSnapshotDecoder {
    static func decode(from data: Data) -> BrowserMediaSourceSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseISO8601Date(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported ISO-8601 date: \(raw)")
        }
        return try? decoder.decode(BrowserMediaSourceSnapshot.self, from: data)
    }

    private static func parseISO8601Date(_ raw: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: raw) { return date }

        let withoutFractionalSeconds = ISO8601DateFormatter()
        withoutFractionalSeconds.formatOptions = [.withInternetDateTime]
        return withoutFractionalSeconds.date(from: raw)
    }
}

struct EmbeddedWebView: NSViewRepresentable {
    var initialURLString: String
    var onWebViewCreated: (WKWebView) -> Void
    var onNavigationStateChanged: (WebNavigationState) -> Void
    var onOpenInNewTab: (URL) -> Void
    var onSelectionChanged: (BrowserSelectionPayload) -> Void
    var onMediaSnapshotChanged: (BrowserMediaSourceSnapshot) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onNavigationStateChanged: onNavigationStateChanged,
            onOpenInNewTab: onOpenInNewTab,
            onSelectionChanged: onSelectionChanged,
            onMediaSnapshotChanged: onMediaSnapshotChanged
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(source: Self.selectionObserverScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        configuration.userContentController.addUserScript(WKUserScript(source: Self.mediaObserverScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        configuration.userContentController.add(context.coordinator, name: Coordinator.selectionMessageName)
        configuration.userContentController.add(context.coordinator, name: Coordinator.mediaMessageName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        onWebViewCreated(webView)

        webView.loadBrowserURLString(initialURLString)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onNavigationStateChanged = onNavigationStateChanged
        context.coordinator.onOpenInNewTab = onOpenInNewTab
        context.coordinator.onSelectionChanged = onSelectionChanged
        context.coordinator.onMediaSnapshotChanged = onMediaSnapshotChanged
    }

    static let mediaObserverScript = """
    (function() {
      if (window.__connorMediaObserverInstalled) { return; }
      window.__connorMediaObserverInstalled = true;

      var lastPayloadSignature = '';
      var pendingReportTimer = null;
      var observedMediaElements = [];

      function attr(selector, name) {
        var element = document.querySelector(selector);
        return element ? (element.getAttribute(name) || '') : '';
      }

      function collectMediaElements(root, output, visitedRoots) {
        if (!root || visitedRoots.indexOf(root) >= 0) { return; }
        visitedRoots.push(root);
        try {
          if (root.querySelectorAll) {
            Array.prototype.forEach.call(root.querySelectorAll('video,audio'), function(element) {
              if (output.indexOf(element) < 0) { output.push(element); }
            });
            Array.prototype.forEach.call(root.querySelectorAll('*'), function(element) {
              if (element.shadowRoot) { collectMediaElements(element.shadowRoot, output, visitedRoots); }
            });
          }
        } catch (error) {}
      }

      function sourceFor(element) {
        var current = element.currentSrc || element.src || '';
        if (!current && element.querySelector) {
          var source = element.querySelector('source');
          if (source) { current = source.src || source.getAttribute('src') || ''; }
        }
        return current || null;
      }

      function stableIDFor(element, index) {
        if (element.id) { return element.id; }
        var explicit = element.getAttribute && (element.getAttribute('data-connor-media-id') || element.getAttribute('aria-label'));
        if (explicit) { return explicit; }
        var tag = element.tagName ? element.tagName.toLowerCase() : 'media';
        var src = sourceFor(element) || '';
        var rect = element.getBoundingClientRect ? element.getBoundingClientRect() : { x: 0, y: 0, width: 0, height: 0 };
        return tag + '-' + index + '-' + Math.round(rect.x) + '-' + Math.round(rect.y) + '-' + Math.round(rect.width) + '-' + Math.round(rect.height) + '-' + src.slice(0, 80);
      }

      function mediaElements() {
        var elements = [];
        collectMediaElements(document, elements, []);
        observedMediaElements = elements;
        return elements.map(function(element, index) {
          var current = sourceFor(element);
          return {
            id: stableIDFor(element, index),
            kind: element.tagName ? element.tagName.toLowerCase() : 'media',
            sourceURLString: current,
            durationSeconds: isFinite(element.duration) ? element.duration : null,
            currentTimeSeconds: isFinite(element.currentTime) ? element.currentTime : null,
            isPaused: !!element.paused,
            isMuted: !!element.muted,
            readyState: typeof element.readyState === 'number' ? element.readyState : null
          };
        });
      }

      function openGraphMedia() {
        var candidates = [];
        var values = [
          { value: attr('meta[property="og:video"]', 'content') || attr('meta[property="og:video:url"]', 'content') || attr('meta[property="og:video:secure_url"]', 'content'), type: 'video' },
          { value: attr('meta[property="og:audio"]', 'content') || attr('meta[property="og:audio:url"]', 'content') || attr('meta[property="og:audio:secure_url"]', 'content'), type: 'audio' },
          { value: attr('meta[name="twitter:player"]', 'content'), type: 'video' },
          { value: attr('meta[name="twitter:player:stream"]', 'content'), type: 'video' }
        ];
        values.forEach(function(item, index) {
          if (item.value) { candidates.push({ id: 'meta-' + index, sourceURLString: item.value, type: item.type }); }
        });
        return candidates;
      }

      function mediaSessionSelection() {
        try {
          if (!navigator.mediaSession || !navigator.mediaSession.metadata) { return null; }
          var metadata = navigator.mediaSession.metadata;
          var parts = [metadata.title, metadata.artist, metadata.album].filter(Boolean);
          return parts.length ? parts.join(' — ') : null;
        } catch (error) {
          return null;
        }
      }

      function payloadSignature(payload) {
        return JSON.stringify({
          pageURLString: payload.pageURLString,
          pageTitle: payload.pageTitle,
          mediaElements: payload.mediaElements.map(function(item) {
            return {
              id: item.id,
              kind: item.kind,
              sourceURLString: item.sourceURLString,
              durationSeconds: item.durationSeconds,
              isPaused: item.isPaused,
              isMuted: item.isMuted,
              readyState: item.readyState
            };
          }),
          openGraphMedia: payload.openGraphMedia,
          canonicalURLString: payload.canonicalURLString,
          userVisibleSelection: payload.userVisibleSelection
        });
      }

      function reportMediaNow() {
        try {
          var payload = {
            pageURLString: location.href || '',
            pageTitle: document.title || '',
            detectedAt: new Date().toISOString(),
            mediaElements: mediaElements(),
            openGraphMedia: openGraphMedia(),
            canonicalURLString: attr('link[rel="canonical"]', 'href') || null,
            userVisibleSelection: mediaSessionSelection()
          };
          var signature = payloadSignature(payload);
          if (signature === lastPayloadSignature) { return; }
          lastPayloadSignature = signature;
          window.webkit.messageHandlers.connorMedia.postMessage(JSON.stringify(payload));
        } catch (error) {}
      }

      function scheduleReport(delay) {
        if (pendingReportTimer) { clearTimeout(pendingReportTimer); }
        pendingReportTimer = setTimeout(function() {
          pendingReportTimer = null;
          reportMediaNow();
        }, delay || 150);
      }

      function attachMediaEventListeners(element) {
        if (!element || element.__connorMediaListenersInstalled) { return; }
        element.__connorMediaListenersInstalled = true;
        ['loadstart', 'loadedmetadata', 'loadeddata', 'durationchange', 'play', 'playing', 'pause', 'timeupdate', 'volumechange', 'encrypted', 'waitingforkey', 'error'].forEach(function(eventName) {
          element.addEventListener(eventName, function() { scheduleReport(100); }, true);
        });
      }

      function refreshObservedMediaListeners() {
        mediaElements();
        observedMediaElements.forEach(attachMediaEventListeners);
      }

      function instrumentHistory(methodName) {
        var original = history[methodName];
        if (typeof original !== 'function') { return; }
        history[methodName] = function() {
          var result = original.apply(this, arguments);
          setTimeout(function() { refreshObservedMediaListeners(); reportMediaNow(); }, 0);
          setTimeout(function() { refreshObservedMediaListeners(); reportMediaNow(); }, 1000);
          return result;
        };
      }

      refreshObservedMediaListeners();
      reportMediaNow();
      ['play', 'playing', 'pause', 'loadedmetadata', 'durationchange', 'loadeddata'].forEach(function(eventName) {
        document.addEventListener(eventName, function() { refreshObservedMediaListeners(); scheduleReport(100); }, true);
      });
      window.addEventListener('popstate', function() { refreshObservedMediaListeners(); scheduleReport(100); });
      instrumentHistory('pushState');
      instrumentHistory('replaceState');

      if (window.MutationObserver && document.documentElement) {
        var observer = new MutationObserver(function(mutations) {
          var relevant = mutations.some(function(mutation) {
            return mutation.type === 'childList' || mutation.type === 'attributes';
          });
          if (relevant) {
            refreshObservedMediaListeners();
            scheduleReport(250);
          }
        });
        observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['src', 'poster', 'aria-label', 'title'] });
      }

      setTimeout(function() { refreshObservedMediaListeners(); reportMediaNow(); }, 500);
      setTimeout(function() { refreshObservedMediaListeners(); reportMediaNow(); }, 2000);
      setTimeout(function() { refreshObservedMediaListeners(); reportMediaNow(); }, 5000);
      setInterval(function() { refreshObservedMediaListeners(); reportMediaNow(); }, 5000);
    })();
    """

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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        static let selectionMessageName = "connorSelection"
        static let mediaMessageName = "connorMedia"
        weak var webView: WKWebView?
        var onNavigationStateChanged: (WebNavigationState) -> Void
        var onOpenInNewTab: (URL) -> Void
        var onSelectionChanged: (BrowserSelectionPayload) -> Void
        var onMediaSnapshotChanged: (BrowserMediaSourceSnapshot) -> Void

        init(
            onNavigationStateChanged: @escaping (WebNavigationState) -> Void,
            onOpenInNewTab: @escaping (URL) -> Void,
            onSelectionChanged: @escaping (BrowserSelectionPayload) -> Void,
            onMediaSnapshotChanged: @escaping (BrowserMediaSourceSnapshot) -> Void
        ) {
            self.onNavigationStateChanged = onNavigationStateChanged
            self.onOpenInNewTab = onOpenInNewTab
            self.onSelectionChanged = onSelectionChanged
            self.onMediaSnapshotChanged = onMediaSnapshotChanged
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let json = message.body as? String,
                  let data = json.data(using: .utf8)
            else { return }
            if message.name == Self.selectionMessageName,
               let payload = try? JSONDecoder().decode(BrowserSelectionPayload.self, from: data) {
                DispatchQueue.main.async { self.onSelectionChanged(payload) }
                return
            }
            if message.name == Self.mediaMessageName,
               let payload = BrowserMediaSnapshotDecoder.decode(from: data) {
                DispatchQueue.main.async { self.onMediaSnapshotChanged(payload) }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { publishNavigationState(webView) }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { publishNavigationState(webView) }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { publishNavigationState(webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { handleNavigationFailure(in: webView, error: error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { handleNavigationFailure(in: webView, error: error) }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                DispatchQueue.main.async { self.onOpenInNewTab(url) }
            }
            return nil
        }

        private func handleNavigationFailure(in webView: WKWebView, error: Error) {
            if (error as NSError).code == NSURLErrorCancelled {
                publishNavigationState(webView, isLoadingOverride: false)
                return
            }
            showErrorPage(in: webView, error: error)
        }

        private func showErrorPage(in webView: WKWebView, error: Error) {
            let failedURLString = webView.url?.absoluteString ?? ""
            webView.loadHTMLString(
                BrowserBuiltInPage.errorHTML(failedURLString: failedURLString, message: error.localizedDescription),
                baseURL: BrowserBuiltInPage.webViewBaseURL
            )
            publishNavigationState(webView, errorMessage: error.localizedDescription, isLoadingOverride: false)
        }

        private func publishNavigationState(_ webView: WKWebView, errorMessage: String? = nil, isLoadingOverride: Bool? = nil) {
            let state = WebNavigationState(
                canGoBack: webView.canGoBack,
                canGoForward: webView.canGoForward,
                title: webView.title ?? "",
                url: webView.url?.absoluteString ?? "",
                isLoading: isLoadingOverride ?? webView.isLoading,
                errorMessage: errorMessage
            )
            DispatchQueue.main.async { self.onNavigationStateChanged(state) }
        }
    }
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
