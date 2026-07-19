import SwiftUI
import WebKit
import ConnorGraphAppSupport

struct BrowserBackgroundTaskRunnerView: View {
    @Bindable var model: BrowserFeatureModel

    private var runningTasks: [BrowserAssistedTaskState] {
        model.assistedTasksByID.values
            .filter { $0.status == .running && model.shouldAttachAssistedTaskInBackground($0) }
            .sorted { $0.updatedAt < $1.updatedAt }
    }

    var body: some View {
        ZStack {
            ForEach(runningTasks) { task in
                BrowserBackgroundTaskWebView(webView: model.assistedTaskWebView(for: task))
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
    var webView: WKWebView

    func makeNSView(context: Context) -> BrowserWebViewContainerView {
        let container = BrowserWebViewContainerView()
        container.attach(webView)
        return container
    }

    func updateNSView(_ nsView: BrowserWebViewContainerView, context: Context) {
        nsView.attach(webView)
    }
}
