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
    case invalidQuery
}

public struct ConnorDeepLinkNavigator: Sendable {
    private var routeResolver: ConnorNativeShellRouteResolver

    public init(routeResolver: ConnorNativeShellRouteResolver = ConnorNativeShellRouteResolver()) {
        self.routeResolver = routeResolver
    }

    public func resolve(_ url: URL) throws -> ConnorDeepLinkResolution {
        guard url.scheme?.lowercased() == "connor" else {
            throw ConnorDeepLinkNavigatorError.unsupportedScheme(url.scheme)
        }
        guard url.host?.lowercased() == "open", url.user == nil, url.password == nil, url.port == nil else {
            throw ConnorDeepLinkNavigatorError.unsupportedHost(url.host)
        }

        let components = url.pathComponents.dropFirst().filter { $0 != "/" && !$0.isEmpty }
        guard components.count <= 1 else { throw ConnorDeepLinkNavigatorError.unknownDestination(url.path) }
        let destination = components.first ?? "home"
        guard let item = ConnorNativeShellItem(rawValue: destination) else {
            throw ConnorDeepLinkNavigatorError.unknownDestination(destination)
        }

        let route = routeResolver.route(for: item)
        guard route.isPlaceholder == false else {
            throw ConnorDeepLinkNavigatorError.placeholderDestination(destination)
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for key in ["session", "focus"] where query.filter({ $0.name.lowercased() == key }).count > 1 { throw ConnorDeepLinkNavigatorError.invalidQuery }
        if let session = queryValue(named: "session", in: url), !session.isEmpty {
            guard session.count <= 160, session.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw ConnorDeepLinkNavigatorError.invalidQuery }
        }
        if let focus = focusValue(in: url), focus.count > 128 || focus.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) { throw ConnorDeepLinkNavigatorError.invalidQuery }

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
            .first { $0.name.lowercased() == name }?
            .value
    }
}
