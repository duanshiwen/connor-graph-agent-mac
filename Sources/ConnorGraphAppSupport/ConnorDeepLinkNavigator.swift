import Foundation

public struct ConnorDeepLinkResolution: Codable, Sendable, Equatable {
    public var item: ConnorNativeShellItem
    public var sidebarItem: String
    public var requiresBrowserVisible: Bool
    public var focus: String?
    public var sessionID: String?

    public init(
        item: ConnorNativeShellItem,
        sidebarItem: String,
        requiresBrowserVisible: Bool = false,
        focus: String? = nil,
        sessionID: String? = nil
    ) {
        self.item = item
        self.sidebarItem = sidebarItem
        self.requiresBrowserVisible = requiresBrowserVisible
        self.focus = focus
        self.sessionID = sessionID
    }
}

public enum ConnorDeepLinkNavigatorError: Error, Sendable, Equatable {
    case unsupportedScheme(String?)
    case unsupportedHost(String?)
    case missingDestination
    case unknownDestination(String)
    case placeholderDestination(String)
}

public struct ConnorDeepLinkNavigator: Sendable {
    private var routeResolver: ConnorNativeShellRouteResolver

    public init(routeResolver: ConnorNativeShellRouteResolver = ConnorNativeShellRouteResolver()) {
        self.routeResolver = routeResolver
    }

    public func resolve(_ url: URL) throws -> ConnorDeepLinkResolution {
        guard url.scheme == "connor" else {
            throw ConnorDeepLinkNavigatorError.unsupportedScheme(url.scheme)
        }
        guard url.host == "open" else {
            throw ConnorDeepLinkNavigatorError.unsupportedHost(url.host)
        }

        let destination = url.pathComponents.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let destination, !destination.isEmpty else {
            throw ConnorDeepLinkNavigatorError.missingDestination
        }
        guard let item = ConnorNativeShellItem(rawValue: destination) else {
            throw ConnorDeepLinkNavigatorError.unknownDestination(destination)
        }

        let route = routeResolver.route(for: item)
        guard route.isPlaceholder == false else {
            throw ConnorDeepLinkNavigatorError.placeholderDestination(destination)
        }

        return ConnorDeepLinkResolution(
            item: item,
            sidebarItem: route.legacySidebarID,
            requiresBrowserVisible: route.requiresBrowserVisible,
            focus: focusValue(in: url),
            sessionID: queryValue(named: "session", in: url)
        )
    }

    private func focusValue(in url: URL) -> String? {
        queryValue(named: "focus", in: url)
    }

    private func queryValue(named name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}
