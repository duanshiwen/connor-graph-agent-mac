import AppKit
import Foundation
import WebKit
import ConnorGraphAppSupport

@MainActor
final class BrowserLiveWebViewStore {
    struct WebViewLease {
        let webView: WKWebView
        let isNewlyCreated: Bool
    }

    struct SnapshotMetadata {
        var scrollX: Double?
        var scrollY: Double?
        var viewportWidth: Double?
        var viewportHeight: Double?
        var contentFingerprint: String?
        var focusedElementHint: String?
    }

    final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        static let selectionMessageName = "connorSelection"
        static let editableFieldMessageName = "connorEditableField"

        var onNavigationStateChanged: ((WebNavigationState) -> Void)?
        var onAutomationNavigationStateChanged: ((WebNavigationState) -> Void)?
        var onOpenInNewTab: ((URL) -> Void)?
        var onPopupCreated: ((WKWebView, WebViewCoordinator, URL?) -> Void)?
        var onCloseRequested: ((WKWebView) -> Void)?
        var onDownloadChanged: ((BrowserDownloadItem) -> Void)?
        var onDownloadStarted: ((UUID, WKDownload) -> Void)?
        var onDownloadEnded: ((UUID) -> Void)?
        var onMediaPermissionRequest: ((String, BrowserSitePermissionKind, @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) -> Void)?
        var onContentProcessTerminated: ((WKWebView) -> Void)?
        var onSelectionChanged: ((BrowserSelectionPayload) -> Void)?
        var onEditableFieldChanged: ((BrowserEditableFieldPayload) -> Void)?
        var onRestorationReady: ((WKWebView) -> Void)?
        var onAutomationDidFinish: ((WKWebView) -> Void)?
        var onAutomationDidFail: ((WKWebView, Error) -> Void)?
        private var downloadCoordinators: [UUID: BrowserDownloadCoordinator] = [:]

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let json = message.body as? String, let data = json.data(using: .utf8) else { return }
            switch message.name {
            case Self.selectionMessageName:
                guard let payload = try? JSONDecoder().decode(BrowserSelectionPayload.self, from: data) else { return }
                DispatchQueue.main.async { self.onSelectionChanged?(payload) }
            case Self.editableFieldMessageName:
                let decoding = Task.detached(priority: .userInitiated) {
                    try? JSONDecoder().decode(BrowserEditableFieldPayload.self, from: data)
                }
                Task { @MainActor [weak self] in
                    guard let payload = await decoding.value else { return }
                    self?.onEditableFieldChanged?(payload)
                }
            default:
                return
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            publishNavigationState(webView)
            onAutomationDidFinish?(webView)
            DispatchQueue.main.async { self.onRestorationReady?(webView) }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { publishNavigationState(webView) }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { publishNavigationState(webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onAutomationDidFail?(webView, error)
            handleNavigationFailure(in: webView, error: error)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onAutomationDidFail?(webView, error)
            handleNavigationFailure(in: webView, error: error)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil else { return nil }
            let popupCoordinator = WebViewCoordinator()
            popupCoordinator.copyRuntimeHandlers(from: self)
            let popup = BrowserLiveWebViewStore.makeConfiguredWebView(configuration: configuration, coordinator: popupCoordinator, isPrivate: false)
            onPopupCreated?(popup, popupCoordinator, navigationAction.request.url)
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) { onCloseRequested?(webView) }

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseDirectories = parameters.allowsDirectories
            panel.canChooseFiles = !parameters.allowsDirectories
            present(panel, for: webView) { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
            let alert = siteAlert(title: "网页提示", message: message, frame: frame)
            alert.addButton(withTitle: "好")
            present(alert, for: webView) { _ in completionHandler() }
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
            let alert = siteAlert(title: "网页确认", message: message, frame: frame)
            alert.addButton(withTitle: "确认")
            alert.addButton(withTitle: "取消")
            present(alert, for: webView) { completionHandler($0 == .alertFirstButtonReturn) }
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
            let alert = siteAlert(title: "网页输入", message: prompt, frame: frame)
            let input = NSTextField(string: defaultText ?? "")
            input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
            alert.accessoryView = input
            alert.addButton(withTitle: "确认")
            alert.addButton(withTitle: "取消")
            present(alert, for: webView) { completionHandler($0 == .alertFirstButtonReturn ? input.stringValue : nil) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { start(download) }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { start(download) }

        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            let method = challenge.protectionSpace.authenticationMethod
            guard method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            if let credential = challenge.proposedCredential, challenge.previousFailureCount == 0 {
                completionHandler(.useCredential, credential)
                return
            }
            let alert = NSAlert()
            alert.messageText = "需要登录"
            alert.informativeText = "\(challenge.protectionSpace.host) 请求用户名和密码。"
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.spacing = 8
            let username = NSTextField(string: "")
            username.placeholderString = "用户名"
            let password = NSSecureTextField(string: "")
            password.placeholderString = "密码"
            stack.addArrangedSubview(username)
            stack.addArrangedSubview(password)
            stack.frame = NSRect(x: 0, y: 0, width: 320, height: 56)
            alert.accessoryView = stack
            alert.addButton(withTitle: "登录")
            alert.addButton(withTitle: "取消")
            present(alert, for: webView) { response in
                guard response == .alertFirstButtonReturn else { completionHandler(.cancelAuthenticationChallenge, nil); return }
                completionHandler(.useCredential, URLCredential(user: username.stringValue, password: password.stringValue, persistence: .forSession))
            }
        }

        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
            let defaultPort = origin.protocol == "https" ? 443 : (origin.protocol == "http" ? 80 : 0)
            let portSuffix = origin.port > 0 && origin.port != defaultPort ? ":\(origin.port)" : ""
            let originString = "\(origin.protocol)://\(origin.host)\(portSuffix)"
            let kind: BrowserSitePermissionKind = type == .camera ? .camera : .microphone
            onMediaPermissionRequest?(originString, kind, decisionHandler)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { onContentProcessTerminated?(webView) }

        private func start(_ download: WKDownload) {
            let id = UUID()
            let coordinator = BrowserDownloadCoordinator(
                id: id,
                download: download,
                onChanged: { [weak self] in self?.onDownloadChanged?($0) },
                onEnded: { [weak self] id in self?.downloadCoordinators[id] = nil; self?.onDownloadEnded?(id) }
            )
            downloadCoordinators[id] = coordinator
            onDownloadStarted?(id, download)
            download.delegate = coordinator
            coordinator.publishPreparing()
        }

        private func copyRuntimeHandlers(from other: WebViewCoordinator) {
            onNavigationStateChanged = other.onNavigationStateChanged
            onPopupCreated = other.onPopupCreated
            onCloseRequested = other.onCloseRequested
            onDownloadChanged = other.onDownloadChanged
            onDownloadStarted = other.onDownloadStarted
            onDownloadEnded = other.onDownloadEnded
            onMediaPermissionRequest = other.onMediaPermissionRequest
            onContentProcessTerminated = other.onContentProcessTerminated
            onSelectionChanged = other.onSelectionChanged
            onEditableFieldChanged = other.onEditableFieldChanged
            onRestorationReady = other.onRestorationReady
        }

        private func siteAlert(title: String, message: String, frame: WKFrameInfo) -> NSAlert {
            let alert = NSAlert()
            alert.messageText = title
            let host = frame.request.url?.host ?? "此网页"
            alert.informativeText = "\(host)：\n\(message)"
            return alert
        }

        private func present(_ panel: NSOpenPanel, for webView: WKWebView, completion: @escaping (NSApplication.ModalResponse) -> Void) {
            if let window = webView.window { panel.beginSheetModal(for: window, completionHandler: completion) }
            else { completion(panel.runModal()) }
        }

        private func present(_ alert: NSAlert, for webView: WKWebView, completion: @escaping (NSApplication.ModalResponse) -> Void) {
            if let window = webView.window { alert.beginSheetModal(for: window, completionHandler: completion) }
            else { completion(alert.runModal()) }
        }

        private func handleNavigationFailure(in webView: WKWebView, error: Error) {
            if (error as NSError).code == NSURLErrorCancelled {
                publishNavigationState(webView, isLoadingOverride: false)
                return
            }
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
            DispatchQueue.main.async {
                self.onNavigationStateChanged?(state)
                self.onAutomationNavigationStateChanged?(state)
            }
        }
    }

    final class BrowserDownloadCoordinator: NSObject, WKDownloadDelegate {
        let id: UUID
        private weak var download: WKDownload?
        private let sourceURL: URL?
        private let startedAt = Date()
        private let onChanged: (BrowserDownloadItem) -> Void
        private let onEnded: (UUID) -> Void
        private var destinationURL: URL?
        private var filename = "下载项目"
        private var progressObservation: NSKeyValueObservation?

        init(id: UUID, download: WKDownload, onChanged: @escaping (BrowserDownloadItem) -> Void, onEnded: @escaping (UUID) -> Void) {
            self.id = id
            self.download = download
            self.sourceURL = download.originalRequest?.url
            self.onChanged = onChanged
            self.onEnded = onEnded
            super.init()
            progressObservation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
                DispatchQueue.main.async { self?.publish(status: .downloading, progress: progress.fractionCompleted) }
            }
        }

        func publishPreparing() { publish(status: .preparing, progress: 0) }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
            filename = Self.safeFilename(suggestedFilename)
            let destination = Self.uniqueDestination(filename: filename)
            destinationURL = destination
            if destination == nil {
                publish(status: .cancelled, progress: 0)
                onEnded(id)
            } else {
                publish(status: .downloading, progress: 0)
            }
            return destination
        }

        func downloadDidFinish(_ download: WKDownload) { publish(status: .finished, progress: 1); onEnded(id) }
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { publish(status: .failed, progress: download.progress.fractionCompleted, errorMessage: error.localizedDescription); onEnded(id) }

        private func publish(status: BrowserDownloadStatus, progress: Double, errorMessage: String? = nil) {
            onChanged(BrowserDownloadItem(id: id, sourceURL: sourceURL, filename: filename, destinationURL: destinationURL, progress: max(0, min(progress, 1)), status: status, errorMessage: errorMessage, startedAt: startedAt))
        }

        private static func safeFilename(_ value: String) -> String {
            let name = URL(fileURLWithPath: value).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "下载项目" : name
        }

        private static func uniqueDestination(filename: String) -> URL? {
            guard let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return nil }
            let source = URL(fileURLWithPath: filename)
            let stem = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            var candidate = directory.appendingPathComponent(filename)
            var suffix = 2
            while FileManager.default.fileExists(atPath: candidate.path) {
                let nextName = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
                candidate = directory.appendingPathComponent(nextName)
                suffix += 1
            }
            return candidate
        }
    }

    private struct Entry {
        var key: BrowserLiveWebViewKey
        var webView: WKWebView
        var coordinator: WebViewCoordinator
        var lastAccessedAt: Date
        var lastVisibleAt: Date?
        var isVisible: Bool
        var restorationStatus: BrowserLiveWebViewRestorationStatus
    }

    private var entries: [BrowserLiveWebViewKey: Entry] = [:]
    private var activeDownloads: [UUID: WKDownload] = [:]
    private var activeAutomationKeys: Set<BrowserLiveWebViewKey> = []
    private let privateDataStore = WKWebsiteDataStore.nonPersistent()
    private var budgetPolicy = BrowserLiveWebViewBudgetPolicy()
    var onWillEvict: ((BrowserLiveWebViewKey, WKWebView, SnapshotMetadata) -> Void)?

    func leaseWebView(
        key: BrowserLiveWebViewKey,
        initialURLString: String,
        onNavigationStateChanged: @escaping (WebNavigationState) -> Void,
        onOpenInNewTab: @escaping (URL) -> Void,
        onPopupCreated: @escaping (WKWebView, WebViewCoordinator, URL?) -> Void,
        onCloseRequested: @escaping (WKWebView) -> Void,
        onDownloadChanged: @escaping (BrowserDownloadItem) -> Void,
        onMediaPermissionRequest: @escaping (String, BrowserSitePermissionKind, @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) -> Void,
        onContentProcessTerminated: @escaping (WKWebView) -> Void,
        onSelectionChanged: @escaping (BrowserSelectionPayload) -> Void,
        onEditableFieldChanged: @escaping (BrowserEditableFieldPayload) -> Void,
        onRestorationReady: @escaping (WKWebView) -> Void,
        isPrivate: Bool,
        isVisible: Bool
    ) -> WebViewLease {
        let now = Date()
        if var entry = entries[key] {
            entry.lastAccessedAt = now
            entry.isVisible = isVisible
            if isVisible { entry.lastVisibleAt = now }
            entry.coordinator.onNavigationStateChanged = onNavigationStateChanged
            entry.coordinator.onOpenInNewTab = onOpenInNewTab
            configure(entry.coordinator, onPopupCreated: onPopupCreated, onCloseRequested: onCloseRequested, onDownloadChanged: onDownloadChanged, onMediaPermissionRequest: onMediaPermissionRequest, onContentProcessTerminated: onContentProcessTerminated)
            entry.coordinator.onSelectionChanged = onSelectionChanged
            entry.coordinator.onEditableFieldChanged = onEditableFieldChanged
            entry.coordinator.onRestorationReady = onRestorationReady
            entries[key] = entry
            return WebViewLease(webView: entry.webView, isNewlyCreated: false)
        }

        let coordinator = WebViewCoordinator()
        coordinator.onNavigationStateChanged = onNavigationStateChanged
        coordinator.onOpenInNewTab = onOpenInNewTab
        configure(coordinator, onPopupCreated: onPopupCreated, onCloseRequested: onCloseRequested, onDownloadChanged: onDownloadChanged, onMediaPermissionRequest: onMediaPermissionRequest, onContentProcessTerminated: onContentProcessTerminated)
        coordinator.onSelectionChanged = onSelectionChanged
        coordinator.onEditableFieldChanged = onEditableFieldChanged
        coordinator.onRestorationReady = onRestorationReady

        let webView = Self.makeConfiguredWebView(coordinator: coordinator, isPrivate: isPrivate, privateDataStore: privateDataStore)
        let entry = Entry(
            key: key,
            webView: webView,
            coordinator: coordinator,
            lastAccessedAt: now,
            lastVisibleAt: isVisible ? now : nil,
            isVisible: isVisible,
            restorationStatus: .live
        )
        entries[key] = entry
        return WebViewLease(webView: webView, isNewlyCreated: true)
    }

    func adoptPopup(key: BrowserLiveWebViewKey, webView: WKWebView, coordinator: WebViewCoordinator, isVisible: Bool) {
        let now = Date()
        entries[key] = Entry(key: key, webView: webView, coordinator: coordinator, lastAccessedAt: now, lastVisibleAt: isVisible ? now : nil, isVisible: isVisible, restorationStatus: .live)
    }

    func leaseAutomationWebView(
        key: BrowserLiveWebViewKey,
        onNavigationStateChanged: @escaping (WebNavigationState) -> Void,
        onDidFinish: ((WKWebView) -> Void)? = nil,
        onDidFail: ((WKWebView, Error) -> Void)? = nil
    ) -> WebViewLease {
        let now = Date()
        if var entry = entries[key] {
            entry.lastAccessedAt = now
            entry.coordinator.onAutomationNavigationStateChanged = onNavigationStateChanged
            if let onDidFinish { entry.coordinator.onAutomationDidFinish = onDidFinish }
            if let onDidFail { entry.coordinator.onAutomationDidFail = onDidFail }
            if onDidFinish != nil || onDidFail != nil { activeAutomationKeys.insert(key) }
            entries[key] = entry
            return WebViewLease(webView: entry.webView, isNewlyCreated: false)
        }

        let coordinator = WebViewCoordinator()
        coordinator.onAutomationNavigationStateChanged = onNavigationStateChanged
        coordinator.onAutomationDidFinish = onDidFinish
        coordinator.onAutomationDidFail = onDidFail
        let webView = Self.makeConfiguredWebView(coordinator: coordinator, isPrivate: false, privateDataStore: privateDataStore)
        entries[key] = Entry(
            key: key,
            webView: webView,
            coordinator: coordinator,
            lastAccessedAt: now,
            lastVisibleAt: nil,
            isVisible: false,
            restorationStatus: .live
        )
        if onDidFinish != nil || onDidFail != nil { activeAutomationKeys.insert(key) }
        return WebViewLease(webView: webView, isNewlyCreated: true)
    }

    func webView(for key: BrowserLiveWebViewKey) -> WKWebView? {
        entries[key]?.webView
    }

    func clearAutomationCallbacks(for key: BrowserLiveWebViewKey) {
        entries[key]?.coordinator.onAutomationDidFinish = nil
        entries[key]?.coordinator.onAutomationDidFail = nil
        activeAutomationKeys.remove(key)
    }

    func cancelDownload(_ id: UUID) {
        activeDownloads[id]?.cancel { [weak self] _ in self?.activeDownloads[id] = nil }
    }

    func clearPrivateWebsiteData() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        privateDataStore.removeData(ofTypes: types, modifiedSince: .distantPast) {}
    }

    private func configure(
        _ coordinator: WebViewCoordinator,
        onPopupCreated: @escaping (WKWebView, WebViewCoordinator, URL?) -> Void,
        onCloseRequested: @escaping (WKWebView) -> Void,
        onDownloadChanged: @escaping (BrowserDownloadItem) -> Void,
        onMediaPermissionRequest: @escaping (String, BrowserSitePermissionKind, @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) -> Void,
        onContentProcessTerminated: @escaping (WKWebView) -> Void
    ) {
        coordinator.onPopupCreated = onPopupCreated
        coordinator.onCloseRequested = onCloseRequested
        coordinator.onDownloadChanged = onDownloadChanged
        coordinator.onDownloadStarted = { [weak self] id, download in self?.activeDownloads[id] = download }
        coordinator.onDownloadEnded = { [weak self] id in self?.activeDownloads[id] = nil }
        coordinator.onMediaPermissionRequest = onMediaPermissionRequest
        coordinator.onContentProcessTerminated = onContentProcessTerminated
    }

    func markVisible(_ key: BrowserLiveWebViewKey) {
        guard var entry = entries[key] else { return }
        let now = Date()
        entry.isVisible = true
        entry.lastVisibleAt = now
        entry.lastAccessedAt = now
        entries[key] = entry
    }

    func markHidden(_ key: BrowserLiveWebViewKey) {
        guard var entry = entries[key] else { return }
        entry.isVisible = false
        entry.webView.pauseBrowserMediaPlayback()
        entries[key] = entry
    }

    func markAllHidden() {
        for key in Array(entries.keys) { markHidden(key) }
    }

    func remove(_ key: BrowserLiveWebViewKey) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        activeAutomationKeys.remove(key)
        cleanup(entry.webView)
    }

    func enforceBudget(processMemoryMegabytes: Int? = nil) {
        let budgetEntries = entries.values.filter { !activeAutomationKeys.contains($0.key) }.map { entry in
            BrowserLiveWebViewBudgetEntry(
                key: entry.key,
                isVisible: entry.isVisible,
                lastAccessedAt: entry.lastAccessedAt,
                lastVisibleAt: entry.lastVisibleAt,
                restorationStatus: entry.restorationStatus
            )
        }
        let decision = budgetPolicy.evictionDecision(entries: budgetEntries, processMemoryMegabytes: processMemoryMegabytes)
        for key in decision.keysToEvict {
            evict(key)
        }
    }

    private func evict(_ key: BrowserLiveWebViewKey) {
        guard var entry = entries.removeValue(forKey: key) else { return }
        activeAutomationKeys.remove(key)
        let metadata = snapshotMetadata(from: entry.webView)
        onWillEvict?(key, entry.webView, metadata)
        entry.restorationStatus = .evicted
        cleanup(entry.webView)
    }

    private func cleanup(_ webView: WKWebView) {
        webView.pauseBrowserMediaPlayback()
        if webView.isLoading { webView.stopLoading() }
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: WebViewCoordinator.selectionMessageName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: WebViewCoordinator.editableFieldMessageName)
        webView.removeFromSuperview()
    }

    private func snapshotMetadata(from webView: WKWebView) -> SnapshotMetadata {
        SnapshotMetadata(
            scrollX: nil,
            scrollY: nil,
            viewportWidth: Double(webView.bounds.width),
            viewportHeight: Double(webView.bounds.height),
            contentFingerprint: webView.url?.absoluteString,
            focusedElementHint: nil
        )
    }

    private static func makeConfiguredWebView(configuration suppliedConfiguration: WKWebViewConfiguration? = nil, coordinator: WebViewCoordinator, isPrivate: Bool, privateDataStore: WKWebsiteDataStore? = nil) -> WKWebView {
        let configuration = suppliedConfiguration ?? WKWebViewConfiguration()
        if isPrivate, let privateDataStore { configuration.websiteDataStore = privateDataStore }
        let userContentController = WKUserContentController()
        configuration.userContentController = userContentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(source: EmbeddedWebView.selectionObserverScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        configuration.userContentController.addUserScript(WKUserScript(source: EmbeddedWebView.editableFieldObserverScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        configuration.userContentController.add(coordinator, name: WebViewCoordinator.selectionMessageName)
        configuration.userContentController.add(coordinator, name: WebViewCoordinator.editableFieldMessageName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        return webView
    }

    private static func makeConfiguredWebView(configuration: WKWebViewConfiguration, coordinator: WebViewCoordinator, isPrivate: Bool) -> WKWebView {
        makeConfiguredWebView(configuration: configuration, coordinator: coordinator, isPrivate: isPrivate, privateDataStore: nil)
    }
}

final class BrowserWebViewContainerView: NSView {
    private(set) weak var attachedWebView: WKWebView?

    func attach(_ webView: WKWebView) {
        if attachedWebView === webView { return }
        attachedWebView?.removeFromSuperview()
        attachedWebView = webView
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
