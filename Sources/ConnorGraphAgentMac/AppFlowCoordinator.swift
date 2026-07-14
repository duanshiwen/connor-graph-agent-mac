import Foundation

enum AppFlowIntent: Sendable, Equatable {
    case navigate(SidebarItem)
    case openSessionNotification(String)
    case openCalendarSettings
    case followRSSItem(RSSFollowRequest)
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

@MainActor
final class AppFlowCoordinator {
    typealias IntentHandler = @MainActor (AppFlowIntent) -> Void

    private let handleIntent: IntentHandler

    init(handleIntent: @escaping IntentHandler) {
        self.handleIntent = handleIntent
    }

    func send(_ intent: AppFlowIntent) {
        handleIntent(intent)
    }
}
