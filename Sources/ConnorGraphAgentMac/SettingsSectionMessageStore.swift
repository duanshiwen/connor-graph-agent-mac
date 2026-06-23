import Foundation

struct SettingsSectionMessageStore: Equatable {
    private var messages: [ConnorSettingsSection: String] = [:]

    func message(for section: ConnorSettingsSection) -> String? {
        messages[section]
    }

    mutating func set(_ message: String?, for section: ConnorSettingsSection) {
        let normalized = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalized.isEmpty {
            messages.removeValue(forKey: section)
        } else {
            messages[section] = normalized
        }
    }

    mutating func clear(for section: ConnorSettingsSection) {
        messages.removeValue(forKey: section)
    }
}
