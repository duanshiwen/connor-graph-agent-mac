import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

struct ShortcutRecorderSheet: View {
    var title: String
    var currentShortcut: AgentRuntimeKeyboardShortcut
    var onCancel: () -> Void
    var onSave: (AgentRuntimeKeyboardShortcut) -> Void

    @State private var capturedShortcut: AgentRuntimeKeyboardShortcut?
    @State private var message: String = "按下新的快捷键。建议至少包含 ⌘。"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("修改快捷键")
                .font(SettingsListTypography.header)
            Text(title)
                .font(SettingsListTypography.rowTitleSelected)
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                Text((capturedShortcut ?? currentShortcut).displayText)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospaced()
            }
            .frame(height: 86)
            .background(ShortcutCaptureView { shortcut in
                capturedShortcut = shortcut
                message = shortcut.command ? "已捕捉: \(shortcut.displayText)" : "已捕捉: \(shortcut.displayText)。建议包含 ⌘。"
            })
            Text(message)
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
            HStack {
                Button("恢复当前") { capturedShortcut = currentShortcut }
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") { onSave(capturedShortcut ?? currentShortcut) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

struct ShortcutCaptureView: NSViewRepresentable {
    var onCapture: (AgentRuntimeKeyboardShortcut) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onCapture = onCapture
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onCapture = onCapture
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }

    final class CaptureView: NSView {
        var onCapture: ((AgentRuntimeKeyboardShortcut) -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if let shortcut = AgentRuntimeKeyboardShortcut.from(event: event) {
                onCapture?(shortcut)
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

struct EditableShortcutRow: View {
    var title: String
    var subtitle: String
    var shortcut: AgentRuntimeKeyboardShortcut
    var onRecord: () -> Void
    var onReset: () -> Void

    var body: some View {
        HStack(spacing: SettingsListLayout.spaceM) {
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                Text(title).font(SettingsListTypography.rowTitleSelected)
                Text(subtitle).font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
            }
            Spacer(minLength: SettingsListLayout.spaceL)
            Text(shortcut.displayText)
                .font(SettingsListTypography.rowCaptionEmphasized.monospaced())
                .padding(.horizontal, SettingsListLayout.spaceM)
                .padding(.vertical, SettingsListLayout.spaceS)
                .background(.quaternary.opacity(0.30), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusS, style: .continuous))
            Button("修改", action: onRecord)
                .buttonStyle(.bordered)
                .controlSize(.regular)
            Button("默认", action: onReset)
                .buttonStyle(.borderless)
                .controlSize(.regular)
        }
        .frame(minHeight: 56)
    }
}
