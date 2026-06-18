import SwiftUI
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

struct AgentComposerOptionBar: View {
    var selectedSession: AgentSession?
    var composerState: AgentComposerState
    var governanceConfig: AppSessionGovernanceConfig
    var hasRunningBackgroundTask: Bool
    @Binding var isSessionInfoPresented: Bool
    var onAction: (AgentComposerAction) -> Void

    var body: some View {
        HStack(spacing: AgentChatLayout.spaceS) {
            permissionModeMenu

            if let selectedSession {
                sessionStatusMenu(selectedSession)
            }

            Spacer(minLength: AgentChatLayout.spaceS)

            backgroundTasksButton

            Button {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                    isSessionInfoPresented.toggle()
                }
            } label: {
                AgentComposerOptionBadge(
                    title: "信息",
                    systemImage: "info.circle",
                    tint: isSessionInfoPresented ? activeForeground : controlForeground,
                    showsChevron: false,
                    isActive: isSessionInfoPresented,
                    style: .compact
                )
            }
            .buttonStyle(.plain)
            .help("会话信息")
        }
        .padding(.horizontal, 1)
        .padding(.bottom, 2)
    }

    private var backgroundTasksButton: some View {
        Button {
            onAction(.showBackgroundTasks)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                    .fill(hasRunningBackgroundTask ? Color.accentColor.opacity(0.16) : Color.clear)
                if hasRunningBackgroundTask {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "tray.full")
                        .font(.system(size: AgentChatTypography.controlIconSize, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
            .foregroundStyle(hasRunningBackgroundTask ? activeForeground : controlForeground)
        }
        .buttonStyle(.plain)
        .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
        .contentShape(Rectangle())
        .help(hasRunningBackgroundTask ? "查看后台任务（运行中）" : "查看后台任务")
    }

    private var permissionModeMenu: some View {
        Menu {
            ForEach(AgentPermissionMode.allCases.filter { $0 != .allowAll }, id: \.self) { mode in
                Button {
                    onAction(.setPermissionMode(mode))
                } label: {
                    Text(menuOptionTitle(mode.displayName, isSelected: mode == composerState.permissionMode))
                }
            }
        } label: {
            AgentComposerOptionBadge(
                title: composerState.permissionMode.displayName,
                systemImage: permissionModeIcon(composerState.permissionMode),
                tint: permissionModeColor(composerState.permissionMode),
                isActive: true,
                style: .prominent
            )
        }
        .menuStyle(.borderlessButton)
        .help("调整本轮会话权限")
    }

    private func sessionStatusMenu(_ session: AgentSession) -> some View {
        Menu {
            ForEach(selectableStatusDefinitions, id: \.id) { definition in
                if let status = AgentSessionStatus(rawValue: definition.id) {
                    Button {
                        onAction(.setSessionStatus(status))
                    } label: {
                        Text(menuOptionTitle(definition.name, isSelected: status == session.governance.status))
                    }
                }
            }
        } label: {
            let definition = statusDefinition(for: session.governance.status)
            AgentComposerOptionBadge(
                title: definition.name,
                systemImage: definition.systemImage,
                tint: sessionStatusColor(session.governance.status),
                isActive: false,
                style: .prominent
            )
        }
        .menuStyle(.borderlessButton)
        .help("更改会话状态")
    }

    private var selectableStatusDefinitions: [AgentSessionStatusDefinition] {
        governanceConfig.statuses
            .filter { $0.id != AgentSessionStatus.archived.rawValue }
            .filter { AgentSessionStatus(rawValue: $0.id) != nil }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder { return lhs.name < rhs.name }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private func statusDefinition(for status: AgentSessionStatus) -> AgentSessionStatusDefinition {
        governanceConfig.statuses.first(where: { $0.id == status.rawValue })
            ?? AgentSessionStatusDefinition.defaults.first(where: { $0.id == status.rawValue })
            ?? AgentSessionStatusDefinition(id: status.rawValue, name: status.displayName, systemImage: sessionStatusIcon(status))
    }

    private var controlForeground: Color { .secondary }

    private var activeForeground: Color { .accentColor }

    private func menuOptionTitle(_ title: String, isSelected: Bool) -> String {
        "\(isSelected ? "✓" : "  ")  \(title)"
    }

    private func permissionModeIcon(_ mode: AgentPermissionMode) -> String {
        switch mode {
        case .readOnly: "eye"
        case .askToWrite: "exclamationmark.circle"
        case .trustedWrite: "pencil.and.outline"
        case .allowAll: "bolt.circle"
        }
    }

    private func permissionModeColor(_ mode: AgentPermissionMode) -> Color {
        switch mode {
        case .readOnly, .askToWrite, .trustedWrite, .allowAll: controlForeground
        }
    }

    private func sessionStatusIcon(_ status: AgentSessionStatus) -> String {
        switch status {
        case .todo: "circle"
        case .inProgress: "play.circle"
        case .waiting: "clock"
        case .needsReview: "exclamationmark.bubble"
        case .done: "checkmark.circle"
        case .blocked: "nosign"
        case .cancelled: "xmark.circle"
        case .archived: "archivebox"
        }
    }

    private func sessionStatusColor(_ status: AgentSessionStatus) -> Color {
        switch status {
        case .todo, .inProgress, .waiting, .needsReview, .done, .blocked, .cancelled, .archived: controlForeground
        }
    }
}
