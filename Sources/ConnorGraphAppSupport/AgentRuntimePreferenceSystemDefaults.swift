import Foundation

public struct AgentRuntimePreferenceSystemDefaults: Sendable, Equatable {
    public var displayName: String
    public var timezone: String
    public var preferredLanguage: String
    public var country: String

    public init(
        displayName: String = "",
        timezone: String = "",
        preferredLanguage: String = "",
        country: String = ""
    ) {
        self.displayName = displayName
        self.timezone = timezone
        self.preferredLanguage = preferredLanguage
        self.country = country
    }

    public static func current(
        locale: Locale = .current,
        preferredLanguages: [String] = Locale.preferredLanguages,
        timeZone: TimeZone = .current,
        accountDisplayName: String = AgentRuntimePreferenceSystemDefaults.systemAccountDisplayName()
    ) -> AgentRuntimePreferenceSystemDefaults {
        let languageIdentifier = preferredLanguages.first ?? locale.identifier
        return AgentRuntimePreferenceSystemDefaults(
            displayName: accountDisplayName,
            timezone: timeZone.identifier,
            preferredLanguage: locale.localizedString(forIdentifier: languageIdentifier) ?? languageIdentifier,
            country: AgentRuntimePreferenceSystemDefaults.localizedCountryName(locale: locale)
        )
    }

    public static func systemAccountDisplayName() -> String {
        let fullName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullName.isEmpty { return fullName }
        return NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func localizedCountryName(locale: Locale = .current) -> String {
        guard let regionCode = locale.region?.identifier, !regionCode.isEmpty else { return "" }
        return locale.localizedString(forRegionCode: regionCode) ?? regionCode
    }
}

public extension AgentRuntimePreferenceSettings {
    @discardableResult
    mutating func fillEmptyFields(from systemDefaults: AgentRuntimePreferenceSystemDefaults) -> Bool {
        var didChange = false
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            displayName = systemDefaults.displayName
            didChange = true
        }
        if timezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            timezone = systemDefaults.timezone
            didChange = true
        }
        if preferredLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preferredLanguage = systemDefaults.preferredLanguage
            didChange = true
        }
        if country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            country = systemDefaults.country
            didChange = true
        }
        return didChange
    }
}
