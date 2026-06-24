import Foundation
import ConnorGraphCore

public enum CalendarSourceWizardError: Error, Sendable, Equatable {
    case providerNotConfigurable
    case missingSubscriptionURL
    case missingServerURL
    case missingUsername
    case missingCredential
    case invalidURL(String)
}

public struct CalendarSourceWizardState: Sendable, Equatable {
    public var provider: CalendarSourceKind
    public var displayName: String
    public var subscriptionURLString: String
    public var serverURLString: String
    public var username: String
    public var appPassword: String
    public var syncWindowPastDays: Int
    public var syncWindowFutureDays: Int
    public var enabledCollectionIDs: [CalendarID]

    public init(
        provider: CalendarSourceKind,
        displayName: String = "",
        subscriptionURLString: String = "",
        serverURLString: String = "",
        username: String = "",
        appPassword: String = "",
        syncWindowPastDays: Int = 30,
        syncWindowFutureDays: Int = 365,
        enabledCollectionIDs: [CalendarID] = []
    ) {
        self.provider = provider
        self.displayName = displayName
        self.subscriptionURLString = subscriptionURLString
        self.serverURLString = serverURLString
        self.username = username
        self.appPassword = appPassword
        self.syncWindowPastDays = syncWindowPastDays
        self.syncWindowFutureDays = syncWindowFutureDays
        self.enabledCollectionIDs = enabledCollectionIDs
    }

    public func buildAccount(existingAccountCount: Int, now: Date = Date()) throws -> CalendarAccount {
        guard let profile = CalendarProviderProfile.catalog.first(where: { $0.sourceKind == provider }), profile.isUserConfigurable else {
            throw CalendarSourceWizardError.providerNotConfigurable
        }
        let resolvedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? profile.displayName : displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountID = CalendarAccountID(rawValue: "calendar-account-\(slug(for: "\(provider.rawValue)-\(resolvedDisplayName)-\(existingAccountCount + 1)"))")
        let configuration: CalendarSourceConfiguration
        switch provider {
        case .icsSubscription:
            let url = try parsedURL(subscriptionURLString, missing: .missingSubscriptionURL)
            configuration = CalendarSourceConfiguration(sourceKind: provider, authMode: .none, subscriptionURL: url, syncWindowPastDays: syncWindowPastDays, syncWindowFutureDays: syncWindowFutureDays, enabledCollectionIDs: enabledCollectionIDs)
        case .genericCalDAV, .appleICloudCalDAV, .fastmailCalDAV, .nextcloudCalDAV:
            let url = try parsedURL(serverURLString.isEmpty ? (profile.defaultServerURL?.absoluteString ?? "") : serverURLString, missing: .missingServerURL)
            let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedUsername.isEmpty else { throw CalendarSourceWizardError.missingUsername }
            guard !appPassword.isEmpty else { throw CalendarSourceWizardError.missingCredential }
            configuration = CalendarSourceConfiguration(sourceKind: provider, authMode: .appPassword, serverURL: url, username: trimmedUsername, syncWindowPastDays: syncWindowPastDays, syncWindowFutureDays: syncWindowFutureDays, enabledCollectionIDs: enabledCollectionIDs)
        case .macOSEventKit:
            configuration = CalendarSourceConfiguration(sourceKind: provider, authMode: .none, syncWindowPastDays: syncWindowPastDays, syncWindowFutureDays: syncWindowFutureDays, enabledCollectionIDs: enabledCollectionIDs)
        case .googleCalendar, .microsoft365Calendar:
            throw CalendarSourceWizardError.providerNotConfigurable
        }
        return CalendarAccount(
            id: accountID,
            provider: provider.legacyConnectedAccountProvider,
            sourceKind: provider,
            displayName: resolvedDisplayName,
            configuration: configuration,
            health: CalendarAccountHealth(status: .needsConfiguration, checkedAt: now, summary: "Calendar source created; initial sync pending"),
            createdAt: now,
            updatedAt: now
        )
    }

    public func credentialBinding(for accountID: CalendarAccountID) throws -> CalendarCredentialBinding {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else { throw CalendarSourceWizardError.missingUsername }
        return AppCalendarCredentialStore.binding(accountID: accountID, username: trimmedUsername, authMode: .appPassword)
    }

    private func parsedURL(_ raw: String, missing: CalendarSourceWizardError) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw missing }
        guard let url = URL(string: trimmed), url.scheme != nil else { throw CalendarSourceWizardError.invalidURL(trimmed) }
        return url
    }

    private func slug(for value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let scalars = value.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(scalars).replacingOccurrences(of: #"-{2,}"#, with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private extension CalendarSourceKind {
    var legacyConnectedAccountProvider: ConnectedAccountProviderKind {
        switch self {
        case .macOSEventKit: return .localFixture
        case .googleCalendar: return .google
        case .microsoft365Calendar: return .microsoft365
        default: return .genericCalDAVCardDAV
        }
    }
}
