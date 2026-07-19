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
        let previousWebView = nsView.attachedWebView
        nsView.attach(webView)
        if previousWebView !== webView {
            onWebViewCreated(webView)
        }
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

    static let editableFieldObserverScript = #"""
    (function() {
      if (window.__connorEditableObserverInstalled) { return; }
      window.__connorEditableObserverInstalled = true;
      var registry = window.__connorEditableRegistry = window.__connorEditableRegistry || new Map();
      var active = null;
      var focusTimer = null;
      var moveTimer = null;
      var sequence = 0;

      function clean(value, limit) {
        return String(value || '').replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim().slice(0, limit);
      }
      function editable(element) {
        if (!element || element.disabled || element.readOnly) { return false; }
        if (element.isContentEditable) { return true; }
        if (element.tagName === 'TEXTAREA') { return true; }
        if (element.tagName !== 'INPUT') { return false; }
        return ['text', 'search', 'email', 'url', 'tel', 'password'].indexOf((element.type || 'text').toLowerCase()) >= 0;
      }
      function labelFor(element) {
        if (element.labels && element.labels.length) { return clean(Array.from(element.labels).map(function(label) { return label.innerText; }).join(' '), 300); }
        if (element.id) {
          try {
            var explicit = document.querySelector('label[for="' + CSS.escape(element.id) + '"]');
            if (explicit) { return clean(explicit.innerText, 300); }
          } catch (_) {}
        }
        var parent = element.closest('label');
        return parent ? clean(parent.innerText, 300) : '';
      }
      function headingNear(element, selector) {
        var container = element.closest(selector);
        if (!container) { return ''; }
        var heading = container.querySelector('legend,h1,h2,h3,h4,[role="heading"]');
        return heading ? clean(heading.innerText || heading.getAttribute('aria-label'), 300) : '';
      }
      function nearbyText(element) {
        var container = element.closest('[role="dialog"],article,section,fieldset,form,main') || element.parentElement;
        return container ? clean(container.innerText, 1500) : '';
      }
      function sensitiveInfo(element) {
        var type = (element.type || '').toLowerCase();
        var hint = [type, element.name, element.id, element.autocomplete, element.placeholder, element.getAttribute('aria-label'), labelFor(element)].join(' ').toLowerCase();
        var terms = ['password', 'passcode', 'otp', 'one-time-code', 'verification', 'cvv', 'cvc', 'card number', 'credit card', '银行卡', '信用卡', '验证码', '密码', '身份证', '支付'];
        var match = terms.find(function(term) { return hint.indexOf(term) >= 0; });
        return { sensitive: !!match, reason: match ? '此字段可能包含敏感信息' : '' };
      }
      function currentValue(element) {
        if (element.isContentEditable) { return element.innerText || ''; }
        return element.value || '';
      }
      function selectionText(element) {
        if (typeof element.selectionStart === 'number' && typeof element.selectionEnd === 'number') {
          return currentValue(element).slice(element.selectionStart, element.selectionEnd);
        }
        return '';
      }
      function rememberSelection(element, entry) {
        if (typeof element.selectionStart === 'number') {
          entry.start = element.selectionStart;
          entry.end = element.selectionEnd;
        }
      }
      function payloadFor(element, eventName, token) {
        var rect = element.getBoundingClientRect();
        var sensitive = sensitiveInfo(element);
        var value = sensitive.sensitive ? '' : clean(currentValue(element), 2000);
        return {
          event: eventName,
          pageURL: location.href || '', pageTitle: document.title || '', token: token,
          tag: (element.tagName || '').toLowerCase(), type: (element.type || '').toLowerCase(),
          role: element.getAttribute('role') || '', name: element.name || '', label: labelFor(element),
          placeholder: element.placeholder || '', ariaLabel: element.getAttribute('aria-label') || '',
          autocomplete: element.autocomplete || '', maxLength: Number(element.maxLength || -1),
          currentValue: value, selectedText: sensitive.sensitive ? '' : clean(selectionText(element), 1000),
          nearbyText: sensitive.sensitive ? '' : nearbyText(element),
          formTitle: headingNear(element, 'form,fieldset'), sectionTitle: headingNear(element, 'section,article,[role="dialog"],main'),
          rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
          sensitive: sensitive.sensitive, sensitiveReason: sensitive.reason
        };
      }
      function post(element, eventName, token) {
        try {
          var entry = registry.get(token);
          var payload = entry && entry.payload ? Object.assign({}, entry.payload) : payloadFor(element, eventName, token);
          var rect = element.getBoundingClientRect();
          payload.event = eventName;
          payload.rect = { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
          window.webkit.messageHandlers.connorEditableField.postMessage(JSON.stringify(payload));
        } catch (_) {}
      }
      function focus(element) {
        if (!editable(element)) { return; }
        clearTimeout(focusTimer);
        focusTimer = setTimeout(function() {
          if (document.activeElement !== element) { return; }
          var token = element.__connorEditableToken;
          if (!token) { token = 'field-' + Date.now().toString(36) + '-' + (++sequence).toString(36); element.__connorEditableToken = token; }
          var entry = registry.get(token) || { element: element, start: null, end: null };
          entry.element = element;
          entry.payload = payloadFor(element, 'focused', token);
          rememberSelection(element, entry);
          registry.forEach(function(value, key) { if (!value.element || !value.element.isConnected) { registry.delete(key); } });
          registry.set(token, entry);
          active = { element: element, token: token };
          post(element, 'focused', token);
        }, 180);
      }
      function move() {
        if (!active) { return; }
        clearTimeout(moveTimer);
        moveTimer = setTimeout(function() {
          moveTimer = null;
          if (!active || !active.element.isConnected) { return; }
          post(active.element, 'moved', active.token);
        }, 80);
      }
      document.addEventListener('focusin', function(event) { focus(event.target); }, true);
      document.addEventListener('select', function(event) {
        if (!active || event.target !== active.element) { return; }
        var entry = registry.get(active.token); if (entry) { rememberSelection(active.element, entry); }
      }, true);
      document.addEventListener('keyup', function(event) {
        if (!active || event.target !== active.element) { return; }
        var entry = registry.get(active.token); if (entry) { rememberSelection(active.element, entry); }
      }, true);
      window.addEventListener('scroll', move, true);
      window.addEventListener('resize', move, true);
    })();
    """#

    static let editableFieldMutationScript = #"""
    var registry = window.__connorEditableRegistry;
    var entry = registry && registry.get(token);
    var element = entry && entry.element;
    if (!element || !element.isConnected || element.disabled || element.readOnly) {
      return { ok: false, reason: '输入框已失效，请重新选择。', token: token };
    }
    var previous = element.isContentEditable ? (element.innerText || '') : (element.value || '');
    if (expectedCurrentValue !== null && previous !== expectedCurrentValue) {
      return { ok: false, reason: '内容已发生变化，为避免覆盖你的输入，未执行撤销。', token: token };
    }
    var next = text;
    if (mode === 'insert' || mode === 'replaceSelection') {
      if (!element.isContentEditable && typeof entry.start === 'number' && typeof entry.end === 'number') {
        next = previous.slice(0, entry.start) + text + previous.slice(entry.end);
      } else if (mode === 'insert') {
        next = previous + text;
      }
    }
    if (element.isContentEditable) {
      element.focus();
      element.innerText = next;
    } else {
      var prototype = element.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      var setter = Object.getOwnPropertyDescriptor(prototype, 'value');
      if (setter && setter.set) { setter.set.call(element, next); } else { element.value = next; }
      element.focus();
      var caret = next.length;
      if (typeof element.setSelectionRange === 'function') { element.setSelectionRange(caret, caret); }
      entry.start = caret; entry.end = caret;
    }
    element.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
    element.dispatchEvent(new Event('change', { bubbles: true }));
    return { ok: true, previousValue: previous, insertedValue: next, token: token };
    """#

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
