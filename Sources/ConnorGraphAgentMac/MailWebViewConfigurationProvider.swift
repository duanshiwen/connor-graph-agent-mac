import WebKit

@MainActor
final class MailWebViewConfigurationProvider {
    static let shared = MailWebViewConfigurationProvider()

    func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = preferences
        return configuration
    }
}
