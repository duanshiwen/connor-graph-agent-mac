import SwiftUI
import AppKit
import ConnorGraphAppSupport

struct AgentToolInvocationDetailOverlay: View {
    var invocation: AgentToolInvocationPresentation
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                header
                    .padding(AgentChatLayout.spaceM)

                ScrollView {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
                        summaryCard
                        AgentToolInvocationRenderer(invocation: invocation)
                        metadataCard
                        rawEventsCard
                    }
                    .frame(maxWidth: 980, alignment: .leading)
                    .padding(.horizontal, AgentChatLayout.spaceXL)
                    .padding(.bottom, AgentChatLayout.spaceXL)
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.97), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous)
                    .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)
            .padding(AgentChatLayout.spaceXL)
        }
    }

    private var header: some View {
        HStack(spacing: AgentChatLayout.spaceS) {
            Label("Tool Invocation", systemImage: invocation.icon)
                .font(AgentChatTypography.meta.weight(.medium))
                .padding(.horizontal, AgentChatLayout.spaceS)
                .frame(height: AgentChatLayout.chipHeight)
                .background(Color.clear, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                        .stroke(severityColor.opacity(0.28), lineWidth: 1)
                )

            Text(invocation.phase.rawValue)
                .font(AgentChatTypography.monoMicro)
                .foregroundStyle(severityColor)
                .padding(.horizontal, 7)
                .frame(height: AgentChatLayout.chipHeight)
                .background(severityColor.opacity(0.10), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))

            Spacer()

            Button(action: { copy(invocation.callID) }) {
                Label("Copy call ID", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: AgentChatTypography.controlIconSize, weight: .semibold))
                    .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
            }
            .buttonStyle(.plain)
            .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
            .contentShape(Rectangle())
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            HStack(alignment: .firstTextBaseline, spacing: AgentChatLayout.spaceS) {
                Text(invocation.title)
                    .font(AgentChatTypography.sectionTitle)
                Text(invocation.toolName)
                    .font(AgentChatTypography.monoMicro)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            if let target = invocation.target, !target.isEmpty {
                Text(target)
                    .font(AgentChatTypography.monoMeta)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            FlowLikeChips(values: summaryChips)
        }
        .toolInvocationCard()
    }

    private var metadataCard: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                metadataLine("Call ID", invocation.callID)
                metadataLine("Run ID", invocation.runID ?? "—")
                metadataLine("Session ID", invocation.sessionID ?? "—")
                metadataLine("Semantic kind", invocation.semanticKind.rawValue)
                metadataLine("Output artifact", invocation.outputArtifactPath ?? "—")
                metadataLine("Truncated", invocation.isOutputTruncated ? "yes" : "no")
            }
            .padding(.top, AgentChatLayout.spaceS)
        } label: {
            Label("Metadata", systemImage: "tag")
                .font(AgentChatTypography.metaEmphasis)
        }
        .toolInvocationCard()
    }

    private var rawEventsCard: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                metadataLine("Requested", invocation.requestedEventID ?? "—")
                metadataLine("Approved", invocation.approvedEventID ?? "—")
                metadataLine("Started", invocation.startedEventID ?? "—")
                metadataLine("Finished", invocation.finishedEventID ?? "—")
                metadataLine("Failed", invocation.failedEventID ?? "—")
                metadataLine("All events", invocation.rawEventIDs.joined(separator: ", "))
            }
            .padding(.top, AgentChatLayout.spaceS)
        } label: {
            Label("Raw Event Index", systemImage: "ladybug")
                .font(AgentChatTypography.metaEmphasis)
        }
        .toolInvocationCard()
    }

    private func metadataLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentChatLayout.spaceS) {
            Text(title)
                .font(AgentChatTypography.metaEmphasis)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(AgentChatTypography.monoMeta)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private var summaryChips: [String] {
        [
            "status: \(invocation.phase.rawValue)",
            "kind: \(invocation.semanticKind.rawValue)",
            invocation.runID.map { "run: \($0)" },
            invocation.sessionID.map { "session: \($0)" }
        ].compactMap { $0 }
    }

    private var severityColor: Color {
        switch invocation.severity {
        case .info: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private extension View {
    func toolInvocationCard() -> some View {
        self
            .padding(AgentChatLayout.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.50), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
    }
}
