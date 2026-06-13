import SwiftUI
import WebKit
import ConnorGraphAppSupport

struct BrowserBackgroundTaskRunnerView: View {
    @ObservedObject var viewModel: AppViewModel

    private var runningTasks: [BrowserAssistedTaskState] {
        viewModel.browserAssistedTasksByID.values
            .filter { $0.status == .running }
            .sorted { $0.updatedAt < $1.updatedAt }
    }

    var body: some View {
        ZStack {
            ForEach(runningTasks) { task in
                BrowserBackgroundTaskWebView(
                    task: task,
                    onCompleted: { state in viewModel.completeBrowserAssistedTask(state.id, message: "Completed in background") },
                    onNeedsUserIntervention: { state, reason in viewModel.revealBrowserAssistedTask(state.id, reason: reason) },
                    onFailed: { state, message in viewModel.failBrowserAssistedTask(state.id, message: message) }
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
            }
        }
        .frame(width: 1, height: 1)
        .opacity(0.01)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BrowserBackgroundTaskWebView: NSViewRepresentable {
    var task: BrowserAssistedTaskState
    var onCompleted: (BrowserAssistedTaskState) -> Void
    var onNeedsUserIntervention: (BrowserAssistedTaskState, String) -> Void
    var onFailed: (BrowserAssistedTaskState, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(task: task, onCompleted: onCompleted, onNeedsUserIntervention: onNeedsUserIntervention, onFailed: onFailed)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        context.coordinator.load(task: task, in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.task = task
        context.coordinator.onCompleted = onCompleted
        context.coordinator.onNeedsUserIntervention = onNeedsUserIntervention
        context.coordinator.onFailed = onFailed
        context.coordinator.load(task: task, in: nsView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var task: BrowserAssistedTaskState
        var onCompleted: (BrowserAssistedTaskState) -> Void
        var onNeedsUserIntervention: (BrowserAssistedTaskState, String) -> Void
        var onFailed: (BrowserAssistedTaskState, String) -> Void
        private var loadedTaskID: UUID?
        private let detector = BrowserAssistedInterventionDetector()

        init(
            task: BrowserAssistedTaskState,
            onCompleted: @escaping (BrowserAssistedTaskState) -> Void,
            onNeedsUserIntervention: @escaping (BrowserAssistedTaskState, String) -> Void,
            onFailed: @escaping (BrowserAssistedTaskState, String) -> Void
        ) {
            self.task = task
            self.onCompleted = onCompleted
            self.onNeedsUserIntervention = onNeedsUserIntervention
            self.onFailed = onFailed
        }

        func load(task: BrowserAssistedTaskState, in webView: WKWebView) {
            guard loadedTaskID != task.id else { return }
            loadedTaskID = task.id
            guard let url = URL(string: task.urlString) else {
                DispatchQueue.main.async { self.onFailed(task, "Invalid browser-assisted task URL") }
                return
            }
            webView.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let urlString = webView.url?.absoluteString ?? task.urlString
            let title = webView.title ?? task.title
            if let reason = detector.interventionReason(urlString: urlString, title: title) {
                DispatchQueue.main.async { self.onNeedsUserIntervention(self.task, reason) }
            } else {
                DispatchQueue.main.async { self.onCompleted(self.task) }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleFailure(webView, error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleFailure(webView, error: error)
        }

        private func handleFailure(_ webView: WKWebView, error: Error) {
            let urlString = webView.url?.absoluteString ?? task.urlString
            let title = webView.title ?? task.title
            let message = error.localizedDescription
            if let reason = detector.interventionReason(urlString: urlString, title: title, errorMessage: message) {
                DispatchQueue.main.async { self.onNeedsUserIntervention(self.task, reason) }
            } else {
                DispatchQueue.main.async { self.onFailed(self.task, message) }
            }
        }
    }
}
