import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

struct SettingsGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
            Text(title)
                .font(SettingsListTypography.header)
            VStack(spacing: 0) {
                content
                    .padding(.horizontal, SettingsListLayout.spaceL)
                    .padding(.vertical, SettingsListLayout.spaceM)
            }
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous)
                    .stroke(Color.secondary.opacity(SettingsListLayout.hairlineOpacity), lineWidth: 1)
            )
        }
    }
}

struct SettingsAppearanceModeRow: View {
    @Binding var selection: ConnorAppearanceMode

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                    Text("外观")
                        .font(SettingsListTypography.rowTitleSelected)
                    Text("选择应用页面的显示主题。")
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Picker("页面显示主题", selection: $selection) {
                ForEach(ConnorAppearanceMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
        .frame(minHeight: SettingsListLayout.prominentRowMinHeight, alignment: .leading)
    }
}

struct SettingsToggleRow: View {
    var title: String
    var subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SettingsListTypography.rowTitleSelected)
                Text(subtitle).font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(minHeight: SettingsListLayout.rowMinHeight)
    }
}

struct SettingsValueRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title).font(SettingsListTypography.rowTitleSelected)
            Spacer()
            Text(value).font(SettingsListTypography.rowTitle).foregroundStyle(.secondary)
        }
        .frame(minHeight: SettingsListLayout.rowMinHeight)
    }
}

struct SettingsTextFieldRow: View {
    var title: String
    var subtitle: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(SettingsListTypography.rowTitleSelected)
            Text(subtitle).font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
            TextField(title, text: $text)
                .font(SettingsListTypography.rowTitle)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct SettingsPickerRow<Selection: Hashable, Content: View>: View {
    var title: String
    var subtitle: String
    @Binding var selection: Selection
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SettingsListTypography.rowTitleSelected)
                Text(subtitle).font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker(title, selection: $selection) { content }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
        }
        .frame(minHeight: SettingsListLayout.rowMinHeight)
    }
}


struct ShortcutRow: View {
    var title: String
    var keys: [String]

    var body: some View {
        HStack {
            Text(title).font(SettingsListTypography.rowTitleSelected)
            Spacer()
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(SettingsListTypography.rowCaptionEmphasized)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.30), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
        }
        .frame(minHeight: SettingsListLayout.compactRowMinHeight)
    }
}

// MARK: - Shortcut editing support

extension AgentRuntimeShortcutAction {
    var supportsGlobalCommandMenu: Bool {
        switch self {
        case .newSession, .toggleBrowser, .focusTopSearch, .openSettings:
            true
        default:
            false
        }
    }
}

extension AgentRuntimeKeyboardShortcut {
    var keyEquivalent: KeyEquivalent {
        switch key.lowercased() {
        case ",": return ","
        case ".": return "."
        case "/": return "/"
        case "[": return "["
        case "]": return "]"
        default:
            return KeyEquivalent(Character(String(key.lowercased().prefix(1))))
        }
    }

    var eventModifierFlags: EventModifiers {
        var flags: EventModifiers = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        return flags
    }

    static func from(event: NSEvent) -> AgentRuntimeKeyboardShortcut? {
        let flags = event.modifierFlags
        let character = event.charactersIgnoringModifiers?.lowercased()
        guard let rawKey = character, !rawKey.isEmpty else { return nil }
        let supported = [",", ".", "/", "[", "]"]
        let key: String
        if let scalar = rawKey.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) {
            key = String(rawKey.prefix(1))
        } else if supported.contains(String(rawKey.prefix(1))) {
            key = String(rawKey.prefix(1))
        } else {
            return nil
        }
        return AgentRuntimeKeyboardShortcut(
            key: key,
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option),
            control: flags.contains(.control)
        )
    }
}
