import SwiftUI
import ConnorGraphCore

struct AgentAttachmentInspectorView: View {
    var attachment: AgentMessageAttachmentRef
    var remoteRefs: [AgentAttachmentRemoteFileRef] = []
    var evidenceCandidates: [AgentAttachmentEvidenceCandidate] = []
    var auditEvents: [AgentAttachmentAuditEvent] = []
    var onReextract: (() -> Void)? = nil
    var onReindex: (() -> Void)? = nil
    var onCreateEvidence: (() -> Void)? = nil
    var onPurgeRemote: ((AgentAttachmentRemoteFileRef) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                    metadataSection
                    providerSection
                    evidenceSection
                    auditSection
                    actionsSection
                }
                .padding(.bottom, AgentChatLayout.spaceL)
            }
        }
        .padding(AgentChatLayout.spaceL)
        .frame(minWidth: 520, minHeight: 560)
    }

    private var header: some View {
        HStack(spacing: AppShellLayout.spaceM) {
            Image(systemName: iconName(for: attachment.kind))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(ConnorCraftPalette.accent)
            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                Text(attachment.displayName)
                    .font(AppTypography.pageTitle)
                    .lineLimit(2)
                Text("Attachment OS Inspector")
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var metadataSection: some View {
        inspectorSection("Metadata") {
            keyValue("ID", attachment.id)
            keyValue("Kind", attachment.kind.rawValue)
            keyValue("Size", ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file))
            keyValue("Lifecycle", attachment.lifecycleStatus.rawValue)
            keyValue("Extraction", attachment.extractionStatus.rawValue)
            keyValue("Manifest", attachment.manifestRelativePath)
            if let preview = attachment.previewText, !preview.isEmpty {
                Text(preview)
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .padding(AgentChatLayout.spaceM)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM))
            }
        }
    }

    private var providerSection: some View {
        inspectorSection("Provider Native Files") {
            if remoteRefs.isEmpty {
                emptyText("No provider cache recorded yet. Local Attachment Store remains source of truth.")
            } else {
                ForEach(remoteRefs) { ref in
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                        keyValue("Provider", ref.provider.rawValue)
                        keyValue("Status", ref.status.rawValue)
                        if let remoteFileID = ref.remoteFileID { keyValue("Remote ID", remoteFileID) }
                        if let remoteURI = ref.remoteURI { keyValue("Remote URI", remoteURI) }
                        keyValue("Retention", ref.retentionSummary)
                        if let zdr = ref.zdrEligible { keyValue("ZDR Eligible", zdr ? "yes" : "no") }
                        Button("Purge remote") { onPurgeRemote?(ref) }
                            .disabled(onPurgeRemote == nil)
                    }
                    .padding(AgentChatLayout.spaceM)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM))
                }
            }
        }
    }

    private var evidenceSection: some View {
        inspectorSection("Memory OS Evidence") {
            if evidenceCandidates.isEmpty {
                emptyText("No evidence candidate yet. Create a candidate for Memory OS provenance review.")
            } else {
                ForEach(evidenceCandidates) { candidate in
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                        keyValue("Candidate", candidate.id)
                        keyValue("Extractor", candidate.extractor.rawValue)
                        Text(candidate.summary).font(AgentChatTypography.meta)
                    }
                }
            }
        }
    }

    private var auditSection: some View {
        inspectorSection("Audit Timeline") {
            if auditEvents.isEmpty {
                emptyText("No audit events loaded in this inspector context.")
            } else {
                ForEach(auditEvents) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.kind.rawValue).font(AgentChatTypography.metaEmphasis)
                        Text(event.summary).font(AgentChatTypography.meta).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        inspectorSection("Actions") {
            HStack {
                Button("Re-extract") { onReextract?() }.disabled(onReextract == nil)
                Button("Re-index") { onReindex?() }.disabled(onReindex == nil)
                Button("Create evidence candidate") { onCreateEvidence?() }.disabled(onCreateEvidence == nil)
            }
            Text("Dangerous actions must go through Connor Policy / audit boundaries before production enablement.")
                .font(AgentChatTypography.meta)
                .foregroundStyle(.secondary)
        }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).font(AgentChatTypography.metaEmphasis).frame(width: 110, alignment: .leading)
            Text(value).font(AgentChatTypography.meta).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text).font(AgentChatTypography.meta).foregroundStyle(.secondary)
    }

    private func iconName(for kind: AgentAttachmentKind) -> String {
        switch kind {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .spreadsheet, .csv: return "tablecells"
        case .archive: return "archivebox"
        case .audio: return "waveform"
        case .video: return "film"
        case .code, .json, .html: return "chevron.left.forwardslash.chevron.right"
        default: return "paperclip"
        }
    }
}
