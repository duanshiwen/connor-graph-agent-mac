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

            HStack(alignment: .top, spacing: 18) {
                ForEach(ConnorAppearanceMode.allCases) { mode in
                    SettingsAppearanceOptionCard(
                        mode: mode,
                        isSelected: selection == mode
                    ) {
                        selection = mode
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(minHeight: 126, alignment: .leading)
    }
}

private struct SettingsAppearanceOptionCard: View {
    private enum Layout {
        static let previewWidth: CGFloat = 96
        static let previewHeight: CGFloat = 60
        static let previewCornerRadius: CGFloat = 10
        static let systemPaneWidth: CGFloat = previewWidth / 2
    }

    var mode: ConnorAppearanceMode
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .frame(width: Layout.previewWidth, height: Layout.previewHeight)
                    .background(previewBackground, in: RoundedRectangle(cornerRadius: Layout.previewCornerRadius, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: Layout.previewCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Layout.previewCornerRadius, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.16), lineWidth: isSelected ? 3 : 1)
                    )
                    .shadow(color: .black.opacity(isSelected ? 0.14 : 0.06), radius: isSelected ? 6 : 3, x: 0, y: 2)

                Text(mode.displayName)
                    .font(SettingsListTypography.rowCaptionEmphasized)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("页面显示主题：\(mode.displayName)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var preview: some View {
        switch mode {
        case .system:
            HStack(spacing: 0) {
                previewPane(isDark: false)
                    .frame(width: Layout.systemPaneWidth, height: Layout.previewHeight)
                    .clipped()
                previewPane(isDark: true)
                    .frame(width: Layout.systemPaneWidth, height: Layout.previewHeight)
                    .clipped()
            }
        case .light:
            previewPane(isDark: false)
                .frame(width: Layout.previewWidth, height: Layout.previewHeight)
        case .dark:
            previewPane(isDark: true)
                .frame(width: Layout.previewWidth, height: Layout.previewHeight)
        }
    }

    private var previewBackground: Color {
        switch mode {
        case .system, .light: Color(nsColor: .windowBackgroundColor)
        case .dark: Color(red: 0.10, green: 0.11, blue: 0.13)
        }
    }

    private func previewPane(isDark: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: isDark
                    ? [Color(red: 0.12, green: 0.14, blue: 0.18), Color(red: 0.02, green: 0.03, blue: 0.05)]
                    : [Color(red: 0.96, green: 0.98, blue: 1.0), Color(red: 0.78, green: 0.88, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 3) {
                    Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.33)).frame(width: 5, height: 5)
                    Circle().fill(Color(red: 1.0, green: 0.77, blue: 0.08)).frame(width: 5, height: 5)
                    Circle().fill(Color(red: 0.21, green: 0.78, blue: 0.35)).frame(width: 5, height: 5)
                }
                .padding(.top, 6)
                .padding(.leading, 7)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.orange)
                    .frame(width: 34, height: 7)
                    .padding(.leading, 7)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.72))
                    .frame(width: 56, height: 23)
                    .padding(.leading, 7)
            }
        }
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
                .controlSize(.large)
                .frame(width: SettingsListLayout.pickerControlWidth, alignment: .trailing)
        }
        .frame(minHeight: SettingsListLayout.rowMinHeight)
    }
}

struct SettingsBirthDatePickerRow: View {
    var title: String
    var subtitle: String
    @Binding var date: Date
    var hasValue: Bool
    var onDateChange: (Date) -> Void
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SettingsListTypography.rowTitleSelected)
                Text(subtitle).font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                DatePicker(
                    title,
                    selection: Binding(
                        get: { date },
                        set: { newValue in
                            date = newValue
                            onDateChange(newValue)
                        }
                    ),
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .controlSize(.large)
                .frame(width: SettingsListLayout.pickerControlWidth, alignment: .trailing)

                Button("清除", action: onClear)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(!hasValue)
            }
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
