import Foundation

enum AppFlowIntent: Sendable, Equatable {
    case navigate(SidebarItem)
    case openSessionNotification(String)
    case openCalendarSettings
    case followRSSItem(RSSFollowRequest)
    case openInteractiveWeb(InteractiveWebOpenRequest)
}

struct RSSFollowRequest: Sendable, Equatable {
    var itemID: String
    var title: String
    var url: URL

    init(itemID: String, title: String, url: URL) {
        self.itemID = itemID
        self.title = title
        self.url = url
    }
}

/// 「打开互动网页」请求：新建会话并用会话浏览器打开站点（审核模式）。
struct InteractiveWebOpenRequest: Sendable, Equatable {
    var url: URL
    var title: String
}

@MainActor
final class AppFlowCoordinator {
    typealias IntentHandler = @MainActor (AppFlowIntent) -> Void

    private var handleIntent: IntentHandler

    init(handleIntent: @escaping IntentHandler) {
        self.handleIntent = handleIntent
    }

    func send(_ intent: AppFlowIntent) {
        handleIntent(intent)
    }

    func replaceHandler(_ handler: @escaping IntentHandler) {
        handleIntent = handler
    }
}
