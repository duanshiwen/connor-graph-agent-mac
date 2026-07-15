import WebKit

@MainActor
final class MailWebViewConfigurationProvider {
    static let shared = MailWebViewConfigurationProvider()

    private let processPool = WKProcessPool()

    func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = processPool
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = preferences
        return configuration
    }

    func sharesMailProcessPool(_ lhs: WKWebViewConfiguration, _ rhs: WKWebViewConfiguration) -> Bool {
        lhs.processPool === rhs.processPool && lhs.processPool === processPool
    }
}
